package main

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPromptSheerWorktreeNameOmitsBranchPrefixFromLabel(t *testing.T) {
	for _, test := range []struct {
		input string
		want  string
	}{
		{input: "feature-name\n", want: "feature-name"},
		{input: "drew/feature-name\n", want: "feature-name"},
		{input: "  feature-name  \n", want: "feature-name"},
		{input: "\n", want: ""},
	} {
		t.Run(strings.TrimSpace(test.input), func(t *testing.T) {
			var output bytes.Buffer
			got, err := promptSheerWorktreeName(strings.NewReader(test.input), &output)
			if err != nil {
				t.Fatal(err)
			}
			if got != test.want {
				t.Fatalf("promptSheerWorktreeName() = %q, want %q", got, test.want)
			}
			if !strings.Contains(output.String(), sheerBranchPrefix) {
				t.Fatalf("prompt output %q does not show branch prefix %q", output.String(), sheerBranchPrefix)
			}
		})
	}
}

func TestCreateSheerWorktreeUsesPrefixedBranchAndStartsInstall(t *testing.T) {
	client, requests, stop := newTestClient(t, []testAPIResponse{
		{Result: map[string]any{
			"type": "worktree_created",
			"worktree": map[string]any{
				"branch":            "drew/feature-name",
				"label":             "feature-name",
				"open_workspace_id": "w2",
				"path":              "/tmp/worktrees/sheer/drew-feature-name",
			},
		}},
		{Result: map[string]any{
			"type": "pane_list",
			"panes": []any{
				map[string]any{
					"pane_id":      "w2:p1",
					"tab_id":       "w2:t1",
					"workspace_id": "w2",
				},
			},
		}},
		{Result: map[string]any{"type": "pane_input_sent"}},
	})
	defer stop()

	oldSheerRepo := sheerRepo
	sheerRepo = "/tmp/sheer"
	defer func() { sheerRepo = oldSheerRepo }()

	binDir := t.TempDir()
	gitLog := filepath.Join(t.TempDir(), "git.log")
	git := filepath.Join(binDir, "git")
	if err := os.WriteFile(git, []byte("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$GIT_LOG\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir)
	t.Setenv("GIT_LOG", gitLog)

	if err := client.newWorkspaceFrom(strings.NewReader("feature-name\n"), io.Discard); err != nil {
		t.Fatal(err)
	}
	gitCalls, err := os.ReadFile(gitLog)
	if err != nil {
		t.Fatal(err)
	}
	wantGitCalls := strings.Join([]string{
		"-C /tmp/sheer check-ref-format --branch drew/feature-name",
		"-C /tmp/sheer fetch origin main",
		"",
	}, "\n")
	if string(gitCalls) != wantGitCalls {
		t.Fatalf("git calls = %q, want %q", gitCalls, wantGitCalls)
	}

	if len(*requests) != 3 {
		t.Fatalf("captured %d requests, want 3", len(*requests))
	}

	create := (*requests)[0]
	if create.Method != "worktree.create" {
		t.Fatalf("first method = %q, want worktree.create", create.Method)
	}
	for key, want := range map[string]any{
		"base":   "origin/main",
		"branch": "drew/feature-name",
		"cwd":    "/tmp/sheer",
		"focus":  false,
		"label":  "feature-name",
	} {
		if got := create.Params[key]; got != want {
			t.Errorf("worktree.create %s = %#v, want %#v", key, got, want)
		}
	}
	if _, setsCustomPath := create.Params["path"]; setsCustomPath {
		t.Errorf("worktree.create unexpectedly overrides Herdr's default path: %#v", create.Params["path"])
	}

	list := (*requests)[1]
	if list.Method != "pane.list" || list.Params["workspace_id"] != "w2" {
		t.Fatalf("pane lookup = %#v, want pane.list for w2", list)
	}

	run := (*requests)[2]
	if run.Method != "pane.send_input" {
		t.Fatalf("setup method = %q, want pane.send_input", run.Method)
	}
	if run.Params["pane_id"] != "w2:p1" || run.Params["text"] != "pnpm install" {
		t.Fatalf("setup request = %#v, want pnpm install in w2:p1", run.Params)
	}
	keys, ok := run.Params["keys"].([]any)
	if !ok || len(keys) != 1 || keys[0] != "Enter" {
		t.Fatalf("setup keys = %#v, want [Enter]", run.Params["keys"])
	}
}
