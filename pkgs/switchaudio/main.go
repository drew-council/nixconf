// Command switchaudio switches the default PipeWire sink,
// by ALSA name or from a fuzzel picker.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"time"

	"switchaudio/internal/audio"
	"switchaudio/internal/pending"
)

// exitInterrupted matches a shell's status for SIGINT.
const exitInterrupted = 130

type options struct {
	// alsaName is the sink to select.
	// When empty, switchaudio opens the picker.
	alsaName string
	// card is activated before selecting the sink.
	card *audio.CardProfile
	// wait, when positive, retries until the sink appears.
	wait time.Duration
}

type app struct {
	audio   audio.Client
	pending pending.Store
	// menu shows input in a picker
	// and returns its output, or false when dismissed.
	menu   func(ctx context.Context, input string) (string, bool, error)
	sleep  func(ctx context.Context, d time.Duration) error
	stdout io.Writer
	stderr io.Writer
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	a := &app{
		audio:   audio.Client{Runner: audio.ExecRunner{}},
		pending: pending.RuntimeStore(),
		menu:    fuzzel,
		sleep:   sleep,
		stdout:  os.Stdout,
		stderr:  os.Stderr,
	}
	code := a.run(ctx, os.Args[1:])
	stop()
	os.Exit(code)
}

func (a *app) run(ctx context.Context, args []string) int {
	opts, err := parseArgs(args, a.stderr)
	if errors.Is(err, flag.ErrHelp) {
		return 0
	}
	if err != nil {
		return 2
	}

	if err := a.execute(ctx, opts); err != nil {
		if ctx.Err() != nil {
			return exitInterrupted
		}
		fmt.Fprintln(a.stderr, err)
		return 1
	}
	return 0
}

// parseArgs parses the command line, reporting usage errors to stderr.
func parseArgs(args []string, stderr io.Writer) (options, error) {
	fs := flag.NewFlagSet("switchaudio", flag.ContinueOnError)
	fs.SetOutput(stderr)
	fs.Usage = func() {
		fmt.Fprintln(stderr, "Usage: switchaudio [flags]\n\nWithout --alsa-name, pick a sink in fuzzel.\n\nFlags:")
		fs.PrintDefaults()
	}
	alsaName := fs.String("alsa-name", "", "switch to the sink with this PipeWire ALSA name")
	cardName := fs.String("card-name", "", "activate this PipeWire card first (requires --card-profile)")
	cardProfile := fs.String("card-profile", "", "card profile to activate (requires --card-name)")
	waitSeconds := fs.Float64("wait", 0, "wait up to this many seconds for the sink to appear (requires --alsa-name)")
	if err := fs.Parse(args); err != nil {
		return options{}, err
	}

	opts := options{alsaName: *alsaName, wait: time.Duration(*waitSeconds * float64(time.Second))}
	var err error
	switch {
	case fs.NArg() > 0:
		err = fmt.Errorf("unexpected arguments: %v", fs.Args())
	case (*cardName == "") != (*cardProfile == ""):
		err = errors.New("--card-name and --card-profile must be used together")
	case *waitSeconds < 0:
		err = errors.New("--wait must not be negative")
	case *waitSeconds > 0 && *alsaName == "":
		err = errors.New("--wait requires --alsa-name")
	}
	if err != nil {
		fmt.Fprintf(stderr, "switchaudio: %v\n", err)
		return options{}, err
	}
	if *cardName != "" {
		opts.card = &audio.CardProfile{Card: *cardName, Profile: *cardProfile}
	}
	return opts, nil
}

func sleep(ctx context.Context, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}
