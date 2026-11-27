package audio

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
)

// fakeRunner answers pactl queries with fixed JSON
// and records every command.
type fakeRunner struct {
	info     string
	sinks    string
	commands [][]string
}

func (f *fakeRunner) Run(_ context.Context, name string, args ...string) (string, error) {
	cmd := append([]string{name}, args...)
	f.commands = append(f.commands, cmd)
	switch strings.Join(cmd, " ") {
	case "pactl --format=json info":
		return f.info, nil
	case "pactl --format=json list sinks":
		return f.sinks, nil
	}
	if name == "wpctl" || slices.Equal(cmd[:min(2, len(cmd))], []string{"pactl", "set-card-profile"}) {
		return "", nil
	}
	return "", fmt.Errorf("unexpected command: %q", cmd)
}

func runnerWithSinks(sinks string) *fakeRunner {
	return &fakeRunner{info: `{"default_sink_name":"sink.usb"}`, sinks: sinks}
}

func TestSinks(t *testing.T) {
	tests := []struct {
		name    string
		info    string
		sinks   string
		want    []Sink
		wantErr string
	}{
		{
			name: "marks selected default",
			sinks: `[
				{"name": "sink.usb", "description": "USB Headset",
				 "properties": {"object.id": "51", "alsa.name": "USB Audio"}},
				{"name": "sink.tv", "description": "TV",
				 "properties": {"object.id": "77", "alsa.name": "LG TV SSCR2"}}
			]`,
			want: []Sink{
				{ID: 51, Name: "sink.usb", ALSAName: "USB Audio", Description: "USB Headset", Selected: true},
				{ID: 77, Name: "sink.tv", ALSAName: "LG TV SSCR2", Description: "TV"},
			},
		},
		{
			name:  "falls back to name",
			sinks: `[{"name": "sink.usb", "description": "", "properties": {"object.id": "51"}}]`,
			want:  []Sink{{ID: 51, Name: "sink.usb", ALSAName: "sink.usb", Description: "sink.usb", Selected: true}},
		},
		{name: "invalid info json", info: `nope`, wantErr: "parsing pactl output"},
		{name: "no default sink", info: `{"default_sink_name": ""}`, wantErr: "pactl did not return a default sink name"},
		{name: "invalid sinks json", sinks: `{}`, wantErr: "parsing pactl output"},
		{name: "bad object id", sinks: `[{"name": "a", "properties": {"object.id": "x"}}]`, wantErr: `sink "a" has invalid object.id "x"`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := runnerWithSinks(tt.sinks)
			if tt.info != "" {
				r.info = tt.info
			}
			got, err := Client{Runner: r}.Sinks(t.Context())
			if tt.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("err = %v, want %q", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(got, tt.want) {
				t.Errorf("got %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestSinkByALSAName(t *testing.T) {
	const usb = `{"name": "sink.usb", "description": "USB Headset",
		"properties": {"object.id": "51", "alsa.name": "USB Audio"}}`
	const dac = `{"name": "sink.usb.2", "description": "USB DAC",
		"properties": {"object.id": "52", "alsa.name": "USB Audio"}}`

	tests := []struct {
		name         string
		sinks        string
		alsaName     string
		wantID       int
		wantErr      string
		wantNotFound bool
	}{
		{name: "exact match", sinks: "[" + usb + "]", alsaName: "USB Audio", wantID: 51},
		{
			name:         "no match",
			sinks:        "[" + usb + "]",
			alsaName:     "LG TV SSCR2",
			wantErr:      "no audio sink found with alsa.name \"LG TV SSCR2\"",
			wantNotFound: true,
		},
		{
			name:     "duplicates",
			sinks:    "[" + usb + "," + dac + "]",
			alsaName: "USB Audio",
			wantErr:  "multiple audio sinks matched alsa.name \"USB Audio\"",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sink, err := Client{Runner: runnerWithSinks(tt.sinks)}.SinkByALSAName(t.Context(), tt.alsaName)
			if tt.wantErr != "" {
				if err == nil || err.Error() != tt.wantErr {
					t.Fatalf("err = %v, want %q", err, tt.wantErr)
				}
				if _, ok := errors.AsType[*SinkNotFoundError](err); ok != tt.wantNotFound {
					t.Errorf("SinkNotFoundError = %v, want %v", ok, tt.wantNotFound)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if sink.ID != tt.wantID {
				t.Errorf("ID = %d, want %d", sink.ID, tt.wantID)
			}
		})
	}
}

func TestSwitchByALSAName(t *testing.T) {
	card := &CardProfile{Card: "alsa_card.pci-0000_03_00.1", Profile: "output:hdmi-stereo-extra3"}
	tests := []struct {
		name     string
		sinks    string
		alsaName string
		card     *CardProfile
		wantName string
		want     [][]string
	}{
		{
			name: "activates card profile first",
			sinks: `[{"name": "sink.tv", "description": "TV",
				"properties": {"object.id": "77", "alsa.name": "HDMI 3"}}]`,
			alsaName: "HDMI 3",
			card:     card,
			wantName: "sink.tv",
			want: [][]string{
				{"pactl", "set-card-profile", "alsa_card.pci-0000_03_00.1", "output:hdmi-stereo-extra3"},
				{"pactl", "--format=json", "info"},
				{"pactl", "--format=json", "list", "sinks"},
				{"pactl", "--format=json", "info"},
				{"pactl", "--format=json", "list", "sinks"},
				{"wpctl", "set-default", "77"},
			},
		},
		{
			name: "prefers card profile sink over alsa name",
			sinks: `[
				{"name": "sink.other", "properties": {"object.id": "5", "alsa.name": "HDMI 3"}},
				{"name": "alsa_output.pci-0000_03_00.1.hdmi-stereo-extra3",
				 "properties": {"object.id": "77", "alsa.name": "LG TV SSCR2"}}
			]`,
			alsaName: "HDMI 3",
			card:     card,
			wantName: "alsa_output.pci-0000_03_00.1.hdmi-stereo-extra3",
			want: [][]string{
				{"pactl", "set-card-profile", "alsa_card.pci-0000_03_00.1", "output:hdmi-stereo-extra3"},
				{"pactl", "--format=json", "info"},
				{"pactl", "--format=json", "list", "sinks"},
				{"wpctl", "set-default", "77"},
			},
		},
		{
			name: "without card profile",
			sinks: `[{"name": "sink.usb", "description": "USB Headset",
				"properties": {"object.id": "51", "alsa.name": "USB Audio"}}]`,
			alsaName: "USB Audio",
			wantName: "sink.usb",
			want: [][]string{
				{"pactl", "--format=json", "info"},
				{"pactl", "--format=json", "list", "sinks"},
				{"wpctl", "set-default", "51"},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := runnerWithSinks(tt.sinks)
			sink, err := Client{Runner: r}.SwitchByALSAName(t.Context(), tt.alsaName, tt.card)
			if err != nil {
				t.Fatal(err)
			}
			if sink.Name != tt.wantName {
				t.Errorf("sink = %q, want %q", sink.Name, tt.wantName)
			}
			if !slices.EqualFunc(r.commands, tt.want, slices.Equal) {
				t.Errorf("commands = %q, want %q", r.commands, tt.want)
			}
		})
	}
}

func TestCardProfileSinkName(t *testing.T) {
	tests := []struct {
		card, profile string
		want          string
		wantOK        bool
	}{
		{"alsa_card.pci-0000_03_00.1", "output:hdmi-stereo-extra3", "alsa_output.pci-0000_03_00.1.hdmi-stereo-extra3", true},
		{"alsa_card.usb-1", "output:analog-stereo+input:mono-fallback", "alsa_output.usb-1.analog-stereo", true},
		{"usb-1", "input:mono+output:iec958-stereo", "alsa_output.usb-1.iec958-stereo", true},
		{"alsa_card.usb-1", "input:mono-fallback", "", false},
		{"alsa_card.usb-1", "off", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.profile, func(t *testing.T) {
			got, ok := CardProfileSinkName(CardProfile{Card: tt.card, Profile: tt.profile})
			if got != tt.want || ok != tt.wantOK {
				t.Errorf("got (%q, %v), want (%q, %v)", got, ok, tt.want, tt.wantOK)
			}
		})
	}
}

func TestExecRunner(t *testing.T) {
	tests := []struct {
		name    string
		script  string
		want    string
		wantErr string
	}{
		{name: "stdout", script: "echo hi", want: "hi\n"},
		{name: "stderr message", script: "echo out; echo ' bad ' >&2; exit 3", wantErr: "bad"},
		{name: "stdout message", script: "echo ' out '; exit 1", wantErr: "out"},
		{name: "no output", script: "exit 1", wantErr: "command failed"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ExecRunner{}.Run(t.Context(), "sh", "-c", tt.script)
			if tt.wantErr != "" {
				if err == nil || err.Error() != tt.wantErr {
					t.Fatalf("err = %v, want %q", err, tt.wantErr)
				}
				return
			}
			if err != nil || got != tt.want {
				t.Errorf("got (%q, %v), want %q", got, err, tt.want)
			}
		})
	}
}
