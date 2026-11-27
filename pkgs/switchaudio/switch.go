package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"switchaudio/internal/audio"
)

const retryInterval = time.Second

func (a *app) execute(ctx context.Context, o options) (err error) {
	if o.wait > 0 {
		var id string
		if id, err = a.pending.Queue(); err != nil {
			return err
		}
		defer func() {
			if clearErr := a.pending.Clear(id); err == nil {
				err = clearErr
			}
		}()
		_, err = a.waitForSink(ctx, id, o)
		return err
	}

	// Any manual choice overrides a queued --wait request.
	if err := a.pending.Clear(""); err != nil {
		return err
	}
	if o.alsaName != "" {
		_, err := a.switchSink(ctx, o)
		return err
	}
	return a.pick(ctx)
}

func (a *app) switchSink(ctx context.Context, o options) (audio.Sink, error) {
	return a.audio.SwitchByALSAName(ctx, o.alsaName, o.card)
}

// waitForSink retries the switch until the sink appears or o.wait elapses.
// It returns false without error when a newer invocation cancels request id.
func (a *app) waitForSink(ctx context.Context, id string, o options) (bool, error) {
	deadline := time.Now().Add(o.wait)
	for {
		switched, err := a.tryPending(ctx, id, o)
		if _, ok := errors.AsType[*audio.SinkNotFoundError](err); !ok {
			return switched, err
		}

		remaining := time.Until(deadline)
		if remaining <= 0 {
			return false, fmt.Errorf("timed out waiting for audio sink %q", o.alsaName)
		}
		if err := a.sleep(ctx, min(retryInterval, remaining)); err != nil {
			return false, err
		}
	}
}

// tryPending switches once if request id is still pending.
func (a *app) tryPending(ctx context.Context, id string, o options) (bool, error) {
	unlock, err := a.pending.Lock()
	if err != nil {
		return false, err
	}
	defer unlock()

	current, err := a.pending.Read()
	if err != nil || current != id {
		return false, err
	}
	if _, err := a.switchSink(ctx, o); err != nil {
		return false, err
	}
	return true, a.pending.Remove()
}

// pick lets the user choose a sink in the menu and makes it the default.
func (a *app) pick(ctx context.Context) error {
	sinks, err := a.audio.Sinks(ctx)
	if err != nil {
		return err
	}
	choices, err := formatChoices(sinks)
	if err != nil {
		return err
	}

	out, ok, err := a.menu(ctx, strings.Join(choices, "\n"))
	if err != nil || !ok {
		return err
	}
	selection := strings.TrimSpace(out)
	if selection == "" {
		return nil
	}
	index, err := strconv.Atoi(selection)
	if err != nil {
		return errors.New("fuzzel returned a non-numeric selection")
	}
	if index < 0 || index >= len(sinks) {
		return errors.New("fuzzel returned an invalid selection")
	}

	sink := sinks[index]
	if err := a.audio.SetDefaultSink(ctx, sink.ID); err != nil {
		return err
	}
	current, err := a.audio.DefaultSinkName(ctx)
	if err != nil {
		return err
	}
	if current != sink.Name {
		return errors.New("failed to update the default audio sink")
	}

	fmt.Fprintf(a.stdout, "switched to %s (%s)\n", sink.Description, sink.Name)
	return nil
}

// formatChoices renders one menu line per sink,
// with the ALSA names aligned and the default sink checked.
func formatChoices(sinks []audio.Sink) ([]string, error) {
	width, selected := 0, 0
	for _, s := range sinks {
		width = max(width, utf8.RuneCountInString(s.ALSAName))
		if s.Selected {
			selected++
		}
	}
	if selected != 1 {
		return nil, errors.New("expected exactly one selected default sink")
	}

	choices := make([]string, len(sinks))
	for i, s := range sinks {
		mark := "  "
		if s.Selected {
			mark = "✅"
		}
		pad := strings.Repeat(" ", width-utf8.RuneCountInString(s.ALSAName))
		choices[i] = mark + " " + s.ALSAName + pad + " " + s.Description
	}
	return choices, nil
}

// fuzzel shows input in a fuzzel dmenu and returns the chosen line's index.
// A non-zero exit means the user dismissed it.
func fuzzel(ctx context.Context, input string) (string, bool, error) {
	var stdout bytes.Buffer
	cmd := exec.CommandContext(ctx, "fuzzel", "--dmenu", "--index", "--use-bold", "--width=50")
	cmd.Stdin = strings.NewReader(input)
	cmd.Stdout = &stdout
	err := cmd.Run()
	if _, ok := errors.AsType[*exec.ExitError](err); ok && ctx.Err() == nil {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return stdout.String(), true, nil
}
