package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunQueuesKnownProfile(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", dir)
	// Stub hyprctl so the test never touches a live compositor.
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "hyprctl"), []byte("#!/bin/sh\necho \"$@\" >> \"$XDG_RUNTIME_DIR/hyprctl.log\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)

	cfg := filepath.Join(dir, "profiles.json")
	err := os.WriteFile(cfg, []byte(`{"profiles":[{"label":"default"},{"label":"desk","useTablet":true}],"tabletHeadlessName":"TAB-1"}`), 0o644)
	if err != nil {
		t.Fatal(err)
	}

	if err := run(cfg, "desk"); err != nil {
		t.Fatal(err)
	}
	request, err := os.ReadFile(filepath.Join(dir, "hyprmonitor-profile-request"))
	if err != nil {
		t.Fatal(err)
	}
	id, label, _ := strings.Cut(string(request), "\n")
	if id == "" || label != "desk\n" {
		t.Errorf("request = %q, want ID then desk", request)
	}
	hyprctl, _ := os.ReadFile(filepath.Join(dir, "hyprctl.log"))
	if got := string(hyprctl); got != "output create headless TAB-1\n" {
		t.Errorf("hyprctl args = %q", got)
	}

	if err := run(cfg, "nope"); err == nil || !strings.Contains(err.Error(), "unknown monitor profile") {
		t.Errorf("err = %v, want unknown profile", err)
	}
}
