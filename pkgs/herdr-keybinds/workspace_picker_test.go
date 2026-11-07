package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestExtraWorkspaceChoicesUsesConfiguredExtraWorkspaces(t *testing.T) {
	home := t.TempDir()

	choices := extraWorkspaceChoices(home)
	want := map[string]string{
		"nixconf": filepath.Join(home, "nixconf"),
		".pi":     filepath.Join(home, ".pi"),
	}
	if len(choices) != len(want) {
		t.Fatalf("expected %d extra workspace choices, got %d", len(want), len(choices))
	}

	for _, choice := range choices {
		wantPath, ok := want[choice.Display]
		if !ok {
			t.Fatalf("unexpected extra workspace choice: %#v", choice)
		}
		if choice.Path != wantPath {
			t.Fatalf("workspace %s path = %q, want %q", choice.Display, choice.Path, wantPath)
		}
	}
}

func TestWorkspaceChoicesForIncludesExistingNixconfExtraChoice(t *testing.T) {
	home := t.TempDir()
	if err := os.Mkdir(filepath.Join(home, "nixconf"), 0o755); err != nil {
		t.Fatal(err)
	}

	choices, err := workspaceChoicesFor(home, nil, extraWorkspaceChoices(home))
	if err != nil {
		t.Fatal(err)
	}

	wantPath := filepath.Join(home, "nixconf")
	for _, choice := range choices {
		if choice.Display == "nixconf" && choice.Path == wantPath {
			return
		}
	}

	t.Fatalf("nixconf workspace choice not found in %#v", choices)
}

func TestWorkspaceLabelForExtraWorkspacesUsesConfiguredPrefix(t *testing.T) {
	home := t.TempDir()
	tests := map[string]string{
		"nixconf": " nixconf",
		".pi":     "π .pi",
	}

	for name, want := range tests {
		if got := workspaceLabelForPath(filepath.Join(home, name)); got != want {
			t.Fatalf("workspaceLabelForPath(%s) = %q, want %q", name, got, want)
		}
	}
}
