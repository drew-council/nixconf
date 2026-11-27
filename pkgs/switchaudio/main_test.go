package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"switchaudio/internal/audio"
	"switchaudio/internal/pending"
)

type fakeSink struct {
	id                    int
	name, alsa, describes string
}

// fakePipeWire answers pactl and wpctl like a live PipeWire server.
type fakePipeWire struct {
	sinks       []fakeSink
	defaultSink string
	commands    []string
	// before runs ahead of each command, for injecting failures or state checks.
	before func(cmd string) error
}

func (f *fakePipeWire) Run(_ context.Context, name string, args ...string) (string, error) {
	cmd := strings.Join(append([]string{name}, args...), " ")
	f.commands = append(f.commands, cmd)
	if f.before != nil {
		if err := f.before(cmd); err != nil {
			return "", err
		}
	}
	switch {
	case cmd == "pactl --format=json info":
		return fmt.Sprintf(`{"default_sink_name": %q}`, f.defaultSink), nil
	case cmd == "pactl --format=json list sinks":
		rows := make([]map[string]any, len(f.sinks))
		for i, s := range f.sinks {
			rows[i] = map[string]any{
				"name":        s.name,
				"description": s.describes,
				"properties":  map[string]any{"object.id": strconv.Itoa(s.id), "alsa.name": s.alsa},
			}
		}
		out, err := json.Marshal(rows)
		return string(out), err
	case strings.HasPrefix(cmd, "wpctl set-default "):
		id, _ := strconv.Atoi(args[1])
		for _, s := range f.sinks {
			if s.id == id {
				f.defaultSink = s.name
			}
		}
		return "", nil
	case strings.HasPrefix(cmd, "pactl set-card-profile "):
		return "", nil
	}
	return "", fmt.Errorf("unexpected command: %s", cmd)
}

var (
	usbSink = fakeSink{51, "sink.usb", "USB Audio", "USB Headset"}
	tvSink  = fakeSink{77, "sink.tv", "LG TV SSCR2", "TV"}
)

type testApp struct {
	*app
	pw             *fakePipeWire
	stdout, stderr strings.Builder
	menuInput      string
	menuCalls      int
}

func newTestApp(t *testing.T, sinks ...fakeSink) *testApp {
	t.Helper()
	ta := &testApp{pw: &fakePipeWire{sinks: sinks, defaultSink: "sink.usb"}}
	ta.app = &app{
		audio:   audio.Client{Runner: ta.pw},
		pending: pending.Store{Dir: t.TempDir()},
		menu: func(context.Context, string) (string, bool, error) {
			t.Fatal("unexpected menu")
			return "", false, nil
		},
		sleep:  func(context.Context, time.Duration) error { return nil },
		stdout: &ta.stdout,
		stderr: &ta.stderr,
	}
	return ta
}

func (ta *testApp) menuReturns(out string, ok bool) {
	ta.menu = func(_ context.Context, input string) (string, bool, error) {
		ta.menuCalls++
		ta.menuInput = input
		return out, ok, nil
	}
}

func (ta *testApp) pendingFile() string {
	return filepath.Join(ta.pending.Dir, "switchaudio-pending")
}

func (ta *testApp) readPending(t *testing.T) string {
	t.Helper()
	id, err := ta.pending.Read()
	if err != nil {
		t.Fatal(err)
	}
	return id
}

func TestWaitRetriesUntilSinkAppears(t *testing.T) {
	ta := newTestApp(t, usbSink)
	attempts := 0
	ta.pw.before = func(cmd string) error {
		if cmd == "pactl --format=json list sinks" {
			attempts++
			if attempts == 2 {
				ta.pw.sinks = append(ta.pw.sinks, tvSink)
			}
		}
		return nil
	}
	sleeps := 0
	ta.sleep = func(_ context.Context, d time.Duration) error {
		sleeps++
		if d > retryInterval {
			t.Errorf("sleep %v exceeds retry interval", d)
		}
		return nil
	}

	if code := ta.run(t.Context(), []string{"--wait", "10", "--alsa-name", "LG TV SSCR2"}); code != 0 {
		t.Fatalf("exit %d: %s", code, ta.stderr.String())
	}
	if attempts != 2 || sleeps != 1 {
		t.Errorf("attempts = %d, sleeps = %d, want 2, 1", attempts, sleeps)
	}
	if ta.pw.defaultSink != "sink.tv" {
		t.Errorf("default sink = %q, want sink.tv", ta.pw.defaultSink)
	}
	if _, err := os.Stat(ta.pendingFile()); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("pending file still exists: %v", err)
	}
}

func TestManualCancellationStopsPendingRetry(t *testing.T) {
	ta := newTestApp(t, usbSink)
	attempts := 0
	ta.pw.before = func(cmd string) error {
		if cmd == "pactl --format=json list sinks" {
			attempts++
		}
		return nil
	}
	// A manual switch from another invocation clears the request mid-wait.
	ta.sleep = func(context.Context, time.Duration) error {
		return ta.pending.Clear("")
	}

	if code := ta.run(t.Context(), []string{"--wait", "10", "--alsa-name", "LG TV SSCR2"}); code != 0 {
		t.Fatalf("exit %d: %s", code, ta.stderr.String())
	}
	if attempts != 1 {
		t.Errorf("attempts = %d, want 1", attempts)
	}
	if ta.pw.defaultSink != "sink.usb" {
		t.Errorf("default sink = %q, want sink.usb", ta.pw.defaultSink)
	}
}

func TestNewerWaitCancelsOlder(t *testing.T) {
	ta := newTestApp(t, usbSink)
	var newer string
	ta.sleep = func(context.Context, time.Duration) error {
		var err error
		newer, err = ta.pending.Queue()
		return err
	}

	if code := ta.run(t.Context(), []string{"--wait", "10", "--alsa-name", "LG TV SSCR2"}); code != 0 {
		t.Fatalf("exit %d: %s", code, ta.stderr.String())
	}
	if got := ta.readPending(t); got != newer {
		t.Errorf("pending = %q, want newer request %q kept", got, newer)
	}
}

func TestWaitTimesOut(t *testing.T) {
	ta := newTestApp(t, usbSink)
	ta.sleep = func(_ context.Context, d time.Duration) error {
		time.Sleep(d)
		return nil
	}

	code := ta.run(t.Context(), []string{"--wait", "0.01", "--alsa-name", "LG TV SSCR2"})
	if code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
	if got, want := ta.stderr.String(), "timed out waiting for audio sink \"LG TV SSCR2\"\n"; got != want {
		t.Errorf("stderr = %q, want %q", got, want)
	}
	if got := ta.readPending(t); got != "" {
		t.Errorf("pending = %q, want cleared", got)
	}
}

func TestManualSwitchCancelsPendingFirst(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "picker", args: nil},
		{name: "alsa name", args: []string{"--alsa-name", "USB Audio"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ta := newTestApp(t, usbSink, tvSink)
			ta.menuReturns("", false)
			if _, err := ta.pending.Queue(); err != nil {
				t.Fatal(err)
			}
			ta.pw.before = func(string) error {
				if id := ta.readPending(t); id != "" {
					t.Errorf("pending request %q not cleared before %v", id, ta.pw.commands)
				}
				return nil
			}

			if code := ta.run(t.Context(), tt.args); code != 0 {
				t.Fatalf("exit %d: %s", code, ta.stderr.String())
			}
			if len(ta.pw.commands) == 0 {
				t.Error("no audio commands ran")
			}
		})
	}
}

func TestPick(t *testing.T) {
	tests := []struct {
		name        string
		menuOut     string
		menuOK      bool
		wantCode    int
		wantDefault string
		wantStdout  string
		wantStderr  string
	}{
		{
			name:        "selects sink",
			menuOut:     "1\n",
			menuOK:      true,
			wantDefault: "sink.tv",
			wantStdout:  "switched to TV (sink.tv)\n",
		},
		{name: "dismissed", menuOK: false, wantDefault: "sink.usb"},
		{name: "empty selection", menuOut: "\n", menuOK: true, wantDefault: "sink.usb"},
		{
			name:        "non-numeric",
			menuOut:     "x",
			menuOK:      true,
			wantCode:    1,
			wantDefault: "sink.usb",
			wantStderr:  "fuzzel returned a non-numeric selection\n",
		},
		{
			name:        "out of range",
			menuOut:     "2",
			menuOK:      true,
			wantCode:    1,
			wantDefault: "sink.usb",
			wantStderr:  "fuzzel returned an invalid selection\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ta := newTestApp(t, usbSink, tvSink)
			ta.menuReturns(tt.menuOut, tt.menuOK)

			if code := ta.run(t.Context(), nil); code != tt.wantCode {
				t.Fatalf("exit %d, want %d: %s", code, tt.wantCode, ta.stderr.String())
			}
			wantInput := "✅ USB Audio   USB Headset\n   LG TV SSCR2 TV"
			if ta.menuInput != wantInput {
				t.Errorf("menu input = %q, want %q", ta.menuInput, wantInput)
			}
			if ta.pw.defaultSink != tt.wantDefault {
				t.Errorf("default sink = %q, want %q", ta.pw.defaultSink, tt.wantDefault)
			}
			if got := ta.stdout.String(); got != tt.wantStdout {
				t.Errorf("stdout = %q, want %q", got, tt.wantStdout)
			}
			if got := ta.stderr.String(); got != tt.wantStderr {
				t.Errorf("stderr = %q, want %q", got, tt.wantStderr)
			}
		})
	}
}

func TestPickRequiresOneDefault(t *testing.T) {
	ta := newTestApp(t, tvSink)
	ta.menuReturns("0", true)

	if code := ta.run(t.Context(), nil); code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
	if got, want := ta.stderr.String(), "expected exactly one selected default sink\n"; got != want {
		t.Errorf("stderr = %q, want %q", got, want)
	}
	if ta.menuCalls != 0 {
		t.Error("menu opened without a default sink")
	}
}

func TestPickVerifiesDefaultChanged(t *testing.T) {
	ta := newTestApp(t, usbSink, tvSink)
	ta.menuReturns("1", true)
	ta.pw.before = func(cmd string) error {
		if strings.HasPrefix(cmd, "wpctl") {
			ta.pw.sinks = nil
		}
		return nil
	}

	if code := ta.run(t.Context(), nil); code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
	if got, want := ta.stderr.String(), "failed to update the default audio sink\n"; got != want {
		t.Errorf("stderr = %q, want %q", got, want)
	}
}

func TestArgs(t *testing.T) {
	tests := []struct {
		name       string
		args       []string
		wantCode   int
		wantStderr string
	}{
		{name: "help", args: []string{"--help"}, wantStderr: "Usage: switchaudio"},
		{name: "wait without alsa name", args: []string{"--wait", "5"}, wantCode: 2, wantStderr: "--wait requires --alsa-name"},
		{name: "negative wait", args: []string{"--wait=-1", "--alsa-name", "x"}, wantCode: 2, wantStderr: "--wait must not be negative"},
		{name: "positional", args: []string{"extra"}, wantCode: 2, wantStderr: "unexpected arguments: [extra]"},
		{name: "unknown flag", args: []string{"--nope"}, wantCode: 2, wantStderr: "flag provided but not defined: -nope"},
		{
			name:       "card name without profile",
			args:       []string{"--alsa-name", "USB Audio", "--card-name", "alsa_card.x"},
			wantCode:   2,
			wantStderr: "--card-name and --card-profile must be used together",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ta := newTestApp(t, usbSink)
			if code := ta.run(t.Context(), tt.args); code != tt.wantCode {
				t.Fatalf("exit %d, want %d: %s", code, tt.wantCode, ta.stderr.String())
			}
			if got := ta.stderr.String(); !strings.Contains(got, tt.wantStderr) {
				t.Errorf("stderr = %q, want it to contain %q", got, tt.wantStderr)
			}
			if len(ta.pw.commands) != 0 {
				t.Errorf("ran audio commands: %v", ta.pw.commands)
			}
		})
	}
}

func TestInterruptExits130(t *testing.T) {
	ta := newTestApp(t, usbSink)
	ctx, cancel := context.WithCancel(t.Context())
	ta.sleep = func(ctx context.Context, d time.Duration) error {
		cancel()
		return sleep(ctx, d)
	}

	if code := ta.run(ctx, []string{"--wait", "10", "--alsa-name", "LG TV SSCR2"}); code != exitInterrupted {
		t.Fatalf("exit %d, want %d", code, exitInterrupted)
	}
	if got := ta.readPending(t); got != "" {
		t.Errorf("pending = %q, want cleared on interrupt", got)
	}
}
