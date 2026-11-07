package sheer

import (
	"io"
	"slices"
	"testing"

	"herdr-keybinds/internal/fetchcache"
	"herdr-keybinds/internal/herdr/herdrtest"
)

func TestOpenChecksOutRemoteOnlyStack(t *testing.T) {
	// gh resolves the repository from its working directory, so the
	// catalog tests need a checkout path that exists.
	root := t.TempDir()
	client, requests, stop := herdrtest.NewServer(t, []herdrtest.Response{
		worktreeListResponse(root),
		mainWorkspaceListResponse(root),
		worktreeCreatedResponse("drew/bottom"),
		paneListResponse(),
		{Result: map[string]any{"type": "pane_input_sent"}},
	})
	defer stop()
	r := testRepo(t, client, root)

	stubSources(t, fakeSources{
		remoteStacks: []string{`[{"number":7,"pull_requests":[{"head":{"ref":"drew/bottom"}},{"head":{"ref":"drew/top"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/bottom\nabc\trefs/heads/drew/top\n",
	})

	if err := r.open("drew/bottom", fetchcache.Fresh); err != nil {
		t.Fatal(err)
	}
	if len(*requests) != 5 {
		t.Fatalf("captured %d requests, want 5", len(*requests))
	}
	create := (*requests)[2]
	if create.Method != "worktree.create" || create.Params["base"] != "origin/drew/bottom" {
		t.Fatalf("create request = %#v, want worktree.create from origin/drew/bottom", create)
	}
	run := (*requests)[4]
	if want := setupCommand("drew/bottom"); run.Params["text"] != want {
		t.Fatalf("setup command = %#v, want %q", run.Params["text"], want)
	}
}

func TestEnsureMainWorkspaceCreatesItOnMain(t *testing.T) {
	client, requests, stop := herdrtest.NewServer(t, []herdrtest.Response{
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
	r := testRepo(t, client, "/tmp/sheer")

	gitCalls := stubGit(t, "")

	workspaceID, err := r.ensureMainWorkspace()
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

func TestCreateWorkspaceBranchesFromMainAndStartsSetup(t *testing.T) {
	client, requests, stop := herdrtest.NewServer(t, []herdrtest.Response{
		mainWorkspaceListResponse("/tmp/sheer"),
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
	r := testRepo(t, client, "/tmp/sheer")

	// Without scripting, the stub git exits 0 with empty output, so config
	// --get reports upstream tracking that must be cleared.
	gitCalls := stubGit(t, "")

	if err := r.createWorkspace(worktreeRequest{Branch: "drew/feature-name"}, io.Discard); err != nil {
		t.Fatal(err)
	}
	wantGitCalls := []string{
		"-C /tmp/sheer check-ref-format --branch drew/feature-name",
		"-C /tmp/sheer fetch origin main",
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
	wantSetup := setupCommand("drew/feature-name")
	if run.Params["pane_id"] != "w2:p1" || run.Params["text"] != wantSetup {
		t.Fatalf("setup request = %#v, want %q in w2:p1", run.Params, wantSetup)
	}
	keys, ok := run.Params["keys"].([]any)
	if !ok || len(keys) != 1 || keys[0] != "Enter" {
		t.Fatalf("setup keys = %#v, want [Enter]", run.Params["keys"])
	}
}

func TestCreateWorkspaceSkipsUnsetForUntrackedBranch(t *testing.T) {
	client, _, stop := herdrtest.NewServer(t, []herdrtest.Response{
		mainWorkspaceListResponse("/tmp/sheer"),
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
	r := testRepo(t, client, "/tmp/sheer")

	// git config --get exits non-zero when the branch has no upstream, which is
	// the state Herdr leaves behind once tracking is cleared.
	gitCalls := stubGit(t, "case \"$*\" in *'config --get'*) exit 1 ;; esac\n")

	if err := r.createWorkspace(worktreeRequest{Branch: "drew/feature-name"}, io.Discard); err != nil {
		t.Fatal(err)
	}
	wantGitCalls := []string{
		"-C /tmp/sheer check-ref-format --branch drew/feature-name",
		"-C /tmp/sheer fetch origin main",
		"-C /tmp/sheer config --get branch.drew/feature-name.merge",
	}
	if got := gitCalls(); !slices.Equal(got, wantGitCalls) {
		t.Fatalf("git calls = %q, want %q", got, wantGitCalls)
	}
}

func TestCreateWorkspaceReusesExistingUpstreamBranch(t *testing.T) {
	client, requests, stop := herdrtest.NewServer(t, []herdrtest.Response{
		mainWorkspaceListResponse("/tmp/sheer"),
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
	r := testRepo(t, client, "/tmp/sheer")

	// The branch already exists upstream, so it must be reused instead of
	// recreated from main.
	gitCalls := stubGit(t, "")

	request := worktreeRequest{Branch: "drew/feature-name", Remote: true}
	if err := r.createWorkspace(request, io.Discard); err != nil {
		t.Fatal(err)
	}
	wantGitCalls := []string{
		"-C /tmp/sheer check-ref-format --branch drew/feature-name",
		"-C /tmp/sheer fetch origin main",
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

func TestCreateWorkspaceChecksOutExistingLocalBranch(t *testing.T) {
	client, requests, stop := herdrtest.NewServer(t, []herdrtest.Response{
		mainWorkspaceListResponse("/tmp/sheer"),
		worktreeCreatedResponse("drew/feature-name"),
		paneListResponse(),
		{Result: map[string]any{"type": "pane_input_sent"}},
	})
	defer stop()
	r := testRepo(t, client, "/tmp/sheer")

	gitCalls := stubGit(t, "")

	request := worktreeRequest{Branch: "drew/feature-name", Local: true}
	if err := r.createWorkspace(request, io.Discard); err != nil {
		t.Fatal(err)
	}
	// The local branch keeps whatever upstream it already has.
	wantGitCalls := []string{
		"-C /tmp/sheer check-ref-format --branch drew/feature-name",
		"-C /tmp/sheer fetch origin main",
	}
	if got := gitCalls(); !slices.Equal(got, wantGitCalls) {
		t.Fatalf("git calls = %q, want %q", got, wantGitCalls)
	}
	if create := (*requests)[1]; create.Params["base"] != "drew/feature-name" {
		t.Fatalf("worktree.create base = %#v, want drew/feature-name", create.Params["base"])
	}
}

func TestSetupCommandChecksOutStackBeforeInit(t *testing.T) {
	want := `let checkout = (gh stack checkout "drew/top" | complete); ` +
		`if $checkout.exit_code == 2 { gh stack init "drew/top" } ` +
		`else { print -n $checkout.stdout; print -n -e $checkout.stderr }; pnpm install`
	if got := setupCommand("drew/top"); got != want {
		t.Errorf("setup = %q, want %q", got, want)
	}
}
