package main

import (
	"io"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
)

func TestNormalizeSheerBranchName(t *testing.T) {
	for _, test := range []struct {
		input string
		want  string
	}{
		{input: "feature-name", want: "feature-name"},
		{input: "drew/feature-name", want: "drew/feature-name"},
		{input: "  drew/feature-name  ", want: "drew/feature-name"},
		{input: "drew/", want: ""},
		{input: "", want: ""},
	} {
		t.Run(test.input, func(t *testing.T) {
			if got := normalizeSheerBranchName(test.input); got != test.want {
				t.Fatalf("normalizeSheerBranchName() = %q, want %q", got, test.want)
			}
		})
	}
}

func TestChooseSheerBranchShowsFullBranchesAndAcceptsSelection(t *testing.T) {
	fzf, inputPath, argsPath := stubFzf(t, "drew/\ndrew/existing\n", 0)
	worktrees := []existingWorktreeInfo{
		{Branch: "other/branch"},
		{Branch: "drew/existing"},
	}

	branch, err := chooseSheerBranch(fzf, worktrees)
	if err != nil {
		t.Fatal(err)
	}
	if branch != "drew/existing" {
		t.Fatalf("selected branch = %q, want drew/existing", branch)
	}

	input, err := os.ReadFile(inputPath)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := string(input), "other/branch\ndrew/existing\n"; got != want {
		t.Fatalf("fzf input = %q, want %q", got, want)
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"--query=drew/",
		"--print-query",
		"--bind=enter:accept-or-print-query",
	} {
		if !strings.Contains(string(args), want) {
			t.Errorf("fzf args %q do not contain %q", args, want)
		}
	}
}

func TestChooseSheerBranchAcceptsNewTypedBranch(t *testing.T) {
	fzf, _, _ := stubFzf(t, "drew/new-branch\ndrew/new-branch\n", 0)

	branch, err := chooseSheerBranch(fzf, nil)
	if err != nil {
		t.Fatal(err)
	}
	if branch != "drew/new-branch" {
		t.Fatalf("selected branch = %q, want drew/new-branch", branch)
	}
}

func TestSheerWorkspacePickerOpensExistingWorktreeUnderMain(t *testing.T) {
	client, requests, stop := newTestClient(t, []testAPIResponse{
		{Result: map[string]any{
			"type": "worktree_list",
			"worktrees": []any{
				map[string]any{
					"branch":             "main",
					"is_linked_worktree": false,
					"path":               "/tmp/sheer",
				},
				map[string]any{
					"branch":             "drew/existing",
					"is_linked_worktree": true,
					"path":               "/tmp/worktrees/sheer/drew-existing",
				},
			},
		}},
		sheerMainWorkspaceListResponse(),
		{Result: map[string]any{"type": "worktree_opened"}},
	})
	defer stop()

	oldSheerRepo := sheerRepo
	sheerRepo = "/tmp/sheer"
	defer func() { sheerRepo = oldSheerRepo }()
	fzf, _, _ := stubFzf(t, "drew/\ndrew/existing\n", 0)

	if err := client.sheerWorkspacePicker(fzf); err != nil {
		t.Fatal(err)
	}
	if len(*requests) != 3 {
		t.Fatalf("captured %d requests, want 3", len(*requests))
	}
	if request := (*requests)[0]; request.Method != "worktree.list" || request.Params["cwd"] != "/tmp/sheer" {
		t.Fatalf("worktree list request = %#v", request)
	}
	if (*requests)[1].Method != "workspace.list" {
		t.Fatalf("second method = %q, want workspace.list", (*requests)[1].Method)
	}
	open := (*requests)[2]
	if open.Method != "worktree.open" {
		t.Fatalf("third method = %q, want worktree.open", open.Method)
	}
	for key, want := range map[string]any{
		"focus":        true,
		"label":        "existing",
		"path":         "/tmp/worktrees/sheer/drew-existing",
		"workspace_id": "w-main",
	} {
		if got := open.Params[key]; got != want {
			t.Errorf("worktree.open %s = %#v, want %#v", key, got, want)
		}
	}
}

func TestEnsureSheerMainWorkspaceCreatesItOnMain(t *testing.T) {
	client, requests, stop := newTestClient(t, []testAPIResponse{
		{Result: map[string]any{"type": "workspace_list", "workspaces": []any{}}},
		{Result: map[string]any{
			"type": "workspace_created",
			"workspace": map[string]any{
				"workspace_id": "w-main",
				"label":        "sheer",
			},
		}},
	})
	defer stop()

	oldSheerRepo := sheerRepo
	sheerRepo = "/tmp/sheer"
	defer func() { sheerRepo = oldSheerRepo }()
	gitCalls := stubGit(t, "")

	workspaceID, err := client.ensureSheerMainWorkspace()
	if err != nil {
		t.Fatal(err)
	}
	if workspaceID != "w-main" {
		t.Fatalf("workspace id = %q, want w-main", workspaceID)
	}
	if got, want := gitCalls(), []string{"-C /tmp/sheer switch main"}; !slices.Equal(got, want) {
		t.Fatalf("git calls = %q, want %q", got, want)
	}
	if len(*requests) != 2 || (*requests)[1].Method != "workspace.create" {
		t.Fatalf("requests = %#v, want workspace.list then workspace.create", *requests)
	}
	create := (*requests)[1]
	for key, want := range map[string]any{
		"cwd":   "/tmp/sheer",
		"focus": false,
		"label": "sheer",
	} {
		if got := create.Params[key]; got != want {
			t.Errorf("workspace.create %s = %#v, want %#v", key, got, want)
		}
	}
}

func TestCreateSheerWorktreeBranchesFromMainAndStartsSetup(t *testing.T) {
	client, requests, stop := newTestClient(t, []testAPIResponse{
		sheerMainWorkspaceListResponse(),
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

	// Without scripting, the stub git exits 0 with empty output, so ls-remote
	// finds no upstream branch and config --get finds no upstream tracking.
	gitCalls := stubGit(t, "")

	if err := client.createSheerWorkspace("drew/feature-name", io.Discard); err != nil {
		t.Fatal(err)
	}
	wantGitCalls := []string{
		"-C /tmp/sheer check-ref-format --branch drew/feature-name",
		"-C /tmp/sheer fetch origin main",
		"-C /tmp/sheer ls-remote --heads origin drew/feature-name",
		"-C /tmp/sheer config --get branch.drew/feature-name.merge",
		"-C /tmp/sheer branch --unset-upstream drew/feature-name",
	}
	if got := gitCalls(); !slices.Equal(got, wantGitCalls) {
		t.Fatalf("git calls = %q, want %q", got, wantGitCalls)
	}

	if len(*requests) != 4 {
		t.Fatalf("captured %d requests, want 4", len(*requests))
	}
	if (*requests)[0].Method != "workspace.list" {
		t.Fatalf("first method = %q, want workspace.list", (*requests)[0].Method)
	}

	create := (*requests)[1]
	if create.Method != "worktree.create" {
		t.Fatalf("second method = %q, want worktree.create", create.Method)
	}
	for key, want := range map[string]any{
		"base":         "origin/main",
		"branch":       "drew/feature-name",
		"focus":        false,
		"label":        "feature-name",
		"workspace_id": "w-main",
	} {
		if got := create.Params[key]; got != want {
			t.Errorf("worktree.create %s = %#v, want %#v", key, got, want)
		}
	}
	if _, setsCustomPath := create.Params["path"]; setsCustomPath {
		t.Errorf("worktree.create unexpectedly overrides Herdr's default path: %#v", create.Params["path"])
	}

	list := (*requests)[2]
	if list.Method != "pane.list" || list.Params["workspace_id"] != "w2" {
		t.Fatalf("pane lookup = %#v, want pane.list for w2", list)
	}

	run := (*requests)[3]
	if run.Method != "pane.send_input" {
		t.Fatalf("setup method = %q, want pane.send_input", run.Method)
	}
	wantSetup := `if ((gh stack view --json | complete).exit_code == 0) { print 'Branch already has a stack; skipping init' } else { gh stack init "drew/feature-name" }; pnpm install`
	if run.Params["pane_id"] != "w2:p1" || run.Params["text"] != wantSetup {
		t.Fatalf("setup request = %#v, want %q in w2:p1", run.Params, wantSetup)
	}
	keys, ok := run.Params["keys"].([]any)
	if !ok || len(keys) != 1 || keys[0] != "Enter" {
		t.Fatalf("setup keys = %#v, want [Enter]", run.Params["keys"])
	}
}

func TestCreateSheerWorktreeSkipsUnsetForUntrackedBranch(t *testing.T) {
	client, _, stop := newTestClient(t, []testAPIResponse{
		sheerMainWorkspaceListResponse(),
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

	// git config --get exits non-zero when the branch has no upstream, which is
	// the state Herdr leaves behind once tracking is cleared.
	gitCalls := stubGit(t, "case \"$*\" in *'config --get'*) exit 1 ;; esac\n")

	if err := client.createSheerWorkspace("drew/feature-name", io.Discard); err != nil {
		t.Fatal(err)
	}
	wantGitCalls := []string{
		"-C /tmp/sheer check-ref-format --branch drew/feature-name",
		"-C /tmp/sheer fetch origin main",
		"-C /tmp/sheer ls-remote --heads origin drew/feature-name",
		"-C /tmp/sheer config --get branch.drew/feature-name.merge",
	}
	if got := gitCalls(); !slices.Equal(got, wantGitCalls) {
		t.Fatalf("git calls = %q, want %q", got, wantGitCalls)
	}
}

func TestCreateSheerWorktreeReusesExistingUpstreamBranch(t *testing.T) {
	client, requests, stop := newTestClient(t, []testAPIResponse{
		sheerMainWorkspaceListResponse(),
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

	// ls-remote prints a ref, so the branch already exists upstream and must be
	// reused instead of recreated from main.
	gitCalls := stubGit(t, "case \"$*\" in *'ls-remote'*) printf 'refs/heads/drew/feature-name\\tabc123\\n' ;; esac\n")

	if err := client.createSheerWorkspace("drew/feature-name", io.Discard); err != nil {
		t.Fatal(err)
	}
	wantGitCalls := []string{
		"-C /tmp/sheer check-ref-format --branch drew/feature-name",
		"-C /tmp/sheer fetch origin main",
		"-C /tmp/sheer ls-remote --heads origin drew/feature-name",
		"-C /tmp/sheer fetch origin drew/feature-name",
	}
	if got := gitCalls(); !slices.Equal(got, wantGitCalls) {
		t.Fatalf("git calls = %q, want %q", got, wantGitCalls)
	}

	if len(*requests) != 4 {
		t.Fatalf("captured %d requests, want 4", len(*requests))
	}
	if (*requests)[0].Method != "workspace.list" {
		t.Fatalf("first method = %q, want workspace.list", (*requests)[0].Method)
	}

	create := (*requests)[1]
	if create.Method != "worktree.create" {
		t.Fatalf("second method = %q, want worktree.create", create.Method)
	}
	for key, want := range map[string]any{
		// Growing the worktree from the existing upstream keeps its tracking,
		// so no upstream clearing happens after creation.
		"base":         "origin/drew/feature-name",
		"branch":       "drew/feature-name",
		"focus":        false,
		"label":        "feature-name",
		"workspace_id": "w-main",
	} {
		if got := create.Params[key]; got != want {
			t.Errorf("worktree.create %s = %#v, want %#v", key, got, want)
		}
	}
}

func sheerMainWorkspaceListResponse() testAPIResponse {
	return testAPIResponse{Result: map[string]any{
		"type": "workspace_list",
		"workspaces": []any{
			map[string]any{
				"workspace_id": "w-main",
				"label":        "sheer",
				"worktree": map[string]any{
					"checkout_path":      "/tmp/sheer",
					"is_linked_worktree": false,
					"repo_key":           "/tmp/sheer/.git",
					"repo_name":          "sheer",
					"repo_root":          "/tmp/sheer",
				},
			},
		},
	}}
}

func stubFzf(t *testing.T, output string, status int) (string, string, string) {
	t.Helper()

	binDir := t.TempDir()
	inputPath := filepath.Join(t.TempDir(), "fzf-input")
	argsPath := filepath.Join(t.TempDir(), "fzf-args")
	fzf := filepath.Join(binDir, "fzf")
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$FZF_ARGS\"\ncat > \"$FZF_INPUT\"\nprintf '%s' \"$FZF_OUTPUT\"\nexit \"$FZF_STATUS\"\n"
	if err := os.WriteFile(fzf, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("FZF_ARGS", argsPath)
	t.Setenv("FZF_INPUT", inputPath)
	t.Setenv("FZF_OUTPUT", output)
	t.Setenv("FZF_STATUS", strconv.Itoa(status))
	return fzf, inputPath, argsPath
}

// stubGit puts a logging git on PATH and returns the recorded argument lines.
// The extra script body runs after logging so tests can control exit codes and
// output.
func stubGit(t *testing.T, script string) func() []string {
	t.Helper()

	binDir := t.TempDir()
	gitLog := filepath.Join(t.TempDir(), "git.log")
	git := filepath.Join(binDir, "git")
	body := "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$GIT_LOG\"\n" + script
	if err := os.WriteFile(git, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir)
	t.Setenv("GIT_LOG", gitLog)

	return func() []string {
		t.Helper()
		calls, err := os.ReadFile(gitLog)
		if err != nil {
			t.Fatal(err)
		}
		return strings.Split(strings.TrimSuffix(string(calls), "\n"), "\n")
	}
}
