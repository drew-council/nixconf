// Package audio reads and switches PipeWire sinks through pactl and wpctl.
package audio

import (
	"bytes"
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// Sink is a PipeWire audio output.
type Sink struct {
	ID          int
	Name        string
	ALSAName    string
	Description string
	Selected    bool
}

// CardProfile is a PipeWire card profile to activate before switching.
type CardProfile struct {
	Card    string
	Profile string
}

// SinkNotFoundError reports that no sink has the requested ALSA name.
// The sink may still appear later, so callers can retry.
type SinkNotFoundError struct {
	ALSAName string
}

func (e *SinkNotFoundError) Error() string {
	return fmt.Sprintf("no audio sink found with alsa.name %q", e.ALSAName)
}

// Runner runs an external command and returns its stdout.
// It fails when the command exits non-zero.
type Runner interface {
	Run(ctx context.Context, name string, args ...string) (string, error)
}

// ExecRunner runs commands from PATH.
type ExecRunner struct{}

// Run reports a failed command by its trimmed stderr,
// falling back to stdout.
func (ExecRunner) Run(ctx context.Context, name string, args ...string) (string, error) {
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
		return "", &CommandError{
			Msg: cmp.Or(strings.TrimSpace(stderr.String()), strings.TrimSpace(stdout.String()), "command failed"),
			Err: exitErr,
		}
	}
	if err != nil {
		return "", err
	}
	return stdout.String(), nil
}

// CommandError is a command that exited non-zero.
// Its message is the command's own output.
type CommandError struct {
	Msg string
	Err error
}

func (e *CommandError) Error() string { return e.Msg }
func (e *CommandError) Unwrap() error { return e.Err }

// Client queries and changes PipeWire state through Runner.
type Client struct {
	Runner Runner
}

// runJSON runs a command and decodes its JSON output into T.
func runJSON[T any](ctx context.Context, c Client, name string, args ...string) (T, error) {
	var v T
	out, err := c.Runner.Run(ctx, name, args...)
	if err != nil {
		return v, err
	}
	if err := json.Unmarshal([]byte(out), &v); err != nil {
		return v, fmt.Errorf("parsing %s output: %w", name, err)
	}
	return v, nil
}

// DefaultSinkName returns the node name of the current default sink.
func (c Client) DefaultSinkName(ctx context.Context) (string, error) {
	info, err := runJSON[struct {
		DefaultSinkName string `json:"default_sink_name"`
	}](ctx, c, "pactl", "--format=json", "info")
	if err != nil {
		return "", err
	}
	if info.DefaultSinkName == "" {
		return "", errors.New("pactl did not return a default sink name")
	}
	return info.DefaultSinkName, nil
}

type pactlSink struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Properties  struct {
		ObjectID string `json:"object.id"`
		ALSAName string `json:"alsa.name"`
	} `json:"properties"`
}

// Sinks lists every sink and marks the default one as selected.
func (c Client) Sinks(ctx context.Context) ([]Sink, error) {
	defaultName, err := c.DefaultSinkName(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := runJSON[[]pactlSink](ctx, c, "pactl", "--format=json", "list", "sinks")
	if err != nil {
		return nil, err
	}

	sinks := make([]Sink, len(rows))
	for i, row := range rows {
		id, err := strconv.Atoi(row.Properties.ObjectID)
		if err != nil {
			return nil, fmt.Errorf("sink %q has invalid object.id %q", row.Name, row.Properties.ObjectID)
		}
		sinks[i] = Sink{
			ID:          id,
			Name:        row.Name,
			ALSAName:    cmp.Or(row.Properties.ALSAName, row.Name),
			Description: cmp.Or(row.Description, row.Name),
			Selected:    row.Name == defaultName,
		}
	}
	return sinks, nil
}

// SinkByALSAName returns the only sink with the given ALSA name.
// It returns *SinkNotFoundError when none match.
func (c Client) SinkByALSAName(ctx context.Context, alsaName string) (Sink, error) {
	sinks, err := c.Sinks(ctx)
	if err != nil {
		return Sink{}, err
	}
	var matches []Sink
	for _, s := range sinks {
		if s.ALSAName == alsaName {
			matches = append(matches, s)
		}
	}
	switch len(matches) {
	case 0:
		return Sink{}, &SinkNotFoundError{ALSAName: alsaName}
	case 1:
		return matches[0], nil
	}
	return Sink{}, fmt.Errorf("multiple audio sinks matched alsa.name %q", alsaName)
}

// SetDefaultSink makes the sink with the given object ID the default.
func (c Client) SetDefaultSink(ctx context.Context, id int) error {
	_, err := c.Runner.Run(ctx, "wpctl", "set-default", strconv.Itoa(id))
	return err
}

// SetCardProfile activates a card profile.
func (c Client) SetCardProfile(ctx context.Context, cp CardProfile) error {
	_, err := c.Runner.Run(ctx, "pactl", "set-card-profile", cp.Card, cp.Profile)
	return err
}

// CardProfileSinkName returns the node name PipeWire gives a card profile's sink.
func CardProfileSinkName(cp CardProfile) (string, bool) {
	card := strings.TrimPrefix(cp.Card, "alsa_card.")
	for part := range strings.SplitSeq(cp.Profile, "+") {
		if output, ok := strings.CutPrefix(part, "output:"); ok {
			return "alsa_output." + card + "." + output, true
		}
	}
	return "", false
}

// SwitchByALSAName makes the sink with the given ALSA name the default.
// When card is set, it activates that profile first
// and prefers the sink the profile creates.
func (c Client) SwitchByALSAName(ctx context.Context, alsaName string, card *CardProfile) (Sink, error) {
	var (
		sink  Sink
		found bool
	)
	if card != nil {
		if err := c.SetCardProfile(ctx, *card); err != nil {
			return Sink{}, err
		}
		// alsa.name is not stable for HDMI:
		// PipeWire replaces it with the display's name
		// once the display is known.
		name, ok := CardProfileSinkName(*card)
		sinks, err := c.Sinks(ctx)
		if err != nil {
			return Sink{}, err
		}
		for _, s := range sinks {
			if ok && s.Name == name {
				sink, found = s, true
				break
			}
		}
	}

	if !found {
		var err error
		if sink, err = c.SinkByALSAName(ctx, alsaName); err != nil {
			return Sink{}, err
		}
	}
	if err := c.SetDefaultSink(ctx, sink.ID); err != nil {
		return Sink{}, err
	}
	return sink, nil
}
