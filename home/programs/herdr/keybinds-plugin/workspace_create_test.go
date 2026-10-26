package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
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

func TestChooseSheerBranchShowsKindsAndAcceptsSelection(t *testing.T) {
	choices := []sheerChoice{
		{
			Kind:   sheerChoiceStack,
			Branch: "drew/top",
			Number: 7,
			Branches: []sheerStackBranch{
				{Name: "drew/merged", Merged: true},
				{Name: "drew/bottom"},
				{Name: "drew/top"},
			},
			Local:  true,
			Remote: true,
		},
		{Kind: sheerChoiceBranch, Branch: "drew/existing", Local: true, Worktree: &existingWorktreeInfo{Branch: "drew/existing"}},
	}
	fzf, inputPath, argsPath := stubFzf(t, "drew/\ndrew/top\t"+choices[0].line(true)+"\n", 0)

	branch, err := chooseSheerBranch(fzf, choices, "")
	if err != nil {
		t.Fatal(err)
	}
	if branch != "drew/top" {
		t.Fatalf("selected branch = %q, want drew/top", branch)
	}

	input, err := os.ReadFile(inputPath)
	if err != nil {
		t.Fatal(err)
	}
	want := "drew/top\t" + choices[0].line(true) + "\n" +
		"drew/existing\t" + choices[1].line(true) + "\n"
	if got := string(input); got != want {
		t.Fatalf("fzf input = %q, want %q", got, want)
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"--ansi",
		"--with-nth=2..",
		"--query=drew/",
		"--print-query",
		"--bind=enter:accept-or-print-query",
		"--bind=alt-enter:print-query",
	} {
		if !strings.Contains(string(args), want) {
			t.Errorf("fzf args %q do not contain %q", args, want)
		}
	}
}

func TestSheerChoiceLine(t *testing.T) {
	stack := sheerChoice{
		Kind:   sheerChoiceStack,
		Branch: "drew/top",
		Number: 29891,
		Branches: []sheerStackBranch{
			{Name: "drew/merged", Merged: true},
			{Name: "drew/bottom"},
			{Name: "drew/top"},
		},
		Local:    true,
		Remote:   true,
		Worktree: &existingWorktreeInfo{Branch: "drew/bottom"},
	}
	if got, want := stack.line(false), "stack   #29891  local+remote  drew/bottom <- drew/top  [worktree]"; got != want {
		t.Errorf("stack line = %q, want %q", got, want)
	}
	branch := sheerChoice{Kind: sheerChoiceBranch, Branch: "drew/feature", Remote: true}
	if got, want := branch.line(false), "branch          remote        drew/feature"; got != want {
		t.Errorf("branch line = %q, want %q", got, want)
	}
}

func TestChooseSheerBranchAcceptsNewTypedBranch(t *testing.T) {
	fzf, _, _ := stubFzf(t, "drew/new-branch\ndrew/new-branch\n", 0)

	branch, err := chooseSheerBranch(fzf, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	if branch != "drew/new-branch" {
		t.Fatalf("selected branch = %q, want drew/new-branch", branch)
	}
}

func TestSheerWorkspacePickerOpensStackWorktreeOnAnotherLayer(t *testing.T) {
	// gh resolves the repository from its working directory, so the
	// catalog tests need a checkout path that exists.
	repo := t.TempDir()
	useSheerRepo(t, repo)
	client, requests, stop := newTestClient(t, []testAPIResponse{
		sheerWorktreeListResponse(repo, map[string]any{
			"branch":             "drew/bottom",
			"is_linked_worktree": true,
			"path":               "/tmp/worktrees/sheer/drew-bottom",
		}),
		sheerMainWorkspaceListResponse(repo),
		{Result: map[string]any{"type": "worktree_opened"}},
	})
	defer stop()

	stubSheerSources(t, sheerSources{
		localStacks:  `{"stacks":[{"number":7,"branches":[{"branch":"drew/bottom"},{"branch":"drew/top"}]}]}`,
		localRefs:    "refs/heads/drew/bottom\t20\nrefs/heads/drew/top\t30\n",
		remoteStacks: []string{`[{"number":7,"pull_requests":[{"head":{"ref":"drew/bottom"}},{"head":{"ref":"drew/top"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/bottom\nabc\trefs/heads/drew/top\n",
	})
	fzf, _, _ := stubFzf(t, "drew/\ndrew/top\tstack\n", 0)

	if err := client.sheerWorkspacePicker(fzf, fetchFresh); err != nil {
		t.Fatal(err)
	}
	if len(*requests) != 3 {
		t.Fatalf("captured %d requests, want 3", len(*requests))
	}
	if request := (*requests)[0]; request.Method != "worktree.list" || request.Params["cwd"] != repo {
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
		"label":        "bottom",
		"path":         "/tmp/worktrees/sheer/drew-bottom",
		"workspace_id": "w-main",
	} {
		if got := open.Params[key]; got != want {
			t.Errorf("worktree.open %s = %#v, want %#v", key, got, want)
		}
	}
}

func TestSheerWorkspacePickerShowsStaleCacheAndReloads(t *testing.T) {
	repo := t.TempDir()
	useSheerRepo(t, repo)
	client, requests, stop := newTestClient(t, []testAPIResponse{
		sheerWorktreeListResponse(repo),
		sheerWorktreeListResponse(repo, map[string]any{
			"branch":             "drew/top",
			"is_linked_worktree": true,
			"path":               "/tmp/worktrees/sheer/drew-top",
		}),
		sheerMainWorkspaceListResponse(repo),
		{Result: map[string]any{"type": "worktree_opened"}},
	})
	defer stop()

	stubSheerSources(t, sheerSources{
		remoteStacks: []string{`[{"number":7,"pull_requests":[{"head":{"ref":"drew/bottom"}},{"head":{"ref":"drew/top"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/bottom\nabc\trefs/heads/drew/top\n",
	})
	ghCalls := stubGitHubStacks(t, `[{"number":7,"pull_requests":[{"head":{"ref":"drew/bottom"}},{"head":{"ref":"drew/top"}}]}]`)
	cache, err := newFetchCache(repo)
	if err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-time.Hour)
	stale := []githubStackPage{{Body: json.RawMessage(`[{"number":3,"pull_requests":[{"head":{"ref":"drew/old"}}]}]`)}}
	if err := cache.write("github-stacks", cacheEnvelope[[]githubStackPage]{FetchedAt: old, Value: stale}); err != nil {
		t.Fatal(err)
	}
	if err := cache.write("origin-heads", cacheEnvelope[map[string]bool]{FetchedAt: old, Value: map[string]bool{"drew/old": true}}); err != nil {
		t.Fatal(err)
	}
	fzf, inputPath, argsPath := stubFzf(t, "drew/\ndrew/top\tstack\n", 0)

	if err := client.sheerWorkspacePicker(fzf, fetchFresh); err != nil {
		t.Fatal(err)
	}

	input, err := os.ReadFile(inputPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(input), "drew/old\t") {
		t.Fatalf("fzf input = %q, want the stale cached stack shown at once", input)
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"--with-shell=sh -c", "--bind=start:reload-sync:", " sheer-workspace list --fzf"} {
		if !strings.Contains(string(args), want) {
			t.Errorf("fzf args %q do not contain %q", args, want)
		}
	}
	// The stub fzf never runs the reload, so the selection is resolved after
	// revalidating the stale cache.
	if got := ghCalls(); len(got) != 1 {
		t.Fatalf("gh calls = %q, want one revalidation after the selection", got)
	}
	if open := (*requests)[3]; open.Method != "worktree.open" || open.Params["path"] != "/tmp/worktrees/sheer/drew-top" {
		t.Fatalf("open request = %#v, want the drew/top worktree", open)
	}
}

func TestSheerWorkspaceListUsesCacheWithinTTL(t *testing.T) {
	repo := t.TempDir()
	useSheerRepo(t, repo)
	client, _, stop := newTestClient(t, []testAPIResponse{
		sheerWorktreeListResponse(repo),
		sheerWorktreeListResponse(repo),
		sheerWorktreeListResponse(repo),
	})
	defer stop()

	gitCalls := stubSheerSources(t, sheerSources{
		remoteStacks: []string{`[{"number":7,"pull_requests":[{"head":{"ref":"drew/top"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/top\n",
	})
	ghCalls := stubGitHubStacks(t, `[{"number":7,"pull_requests":[{"head":{"ref":"drew/top"}}]}]`)

	var first, second bytes.Buffer
	if err := client.sheerWorkspaceList(&first, sheerListText, fetchFresh); err != nil {
		t.Fatal(err)
	}
	if err := client.sheerWorkspaceList(&second, sheerListText, fetchFresh); err != nil {
		t.Fatal(err)
	}
	if first.String() != second.String() || !strings.Contains(first.String(), "#7") {
		t.Fatalf("list output changed or lacks stack #7:\n%s\n%s", first.String(), second.String())
	}
	countLsRemote := func() int {
		count := 0
		for _, call := range gitCalls() {
			if strings.Contains(call, "ls-remote") {
				count++
			}
		}
		return count
	}
	if got := len(ghCalls()); got != 1 {
		t.Fatalf("gh called %d times, want 1", got)
	}
	if got := countLsRemote(); got != 1 {
		t.Fatalf("ls-remote ran %d times, want 1", got)
	}

	if err := client.sheerWorkspaceList(io.Discard, sheerListText, fetchRefresh); err != nil {
		t.Fatal(err)
	}
	if got := ghCalls(); len(got) != 2 || !strings.Contains(got[1], "If-None-Match") {
		t.Fatalf("gh calls after --refresh = %q, want a conditional request", got)
	}
	if got := countLsRemote(); got != 2 {
		t.Fatalf("ls-remote ran %d times after --refresh, want 2", got)
	}
}

func TestSheerWorkspaceBranchChecksOutRemoteOnlyStack(t *testing.T) {
	// gh resolves the repository from its working directory, so the
	// catalog tests need a checkout path that exists.
	repo := t.TempDir()
	useSheerRepo(t, repo)
	client, requests, stop := newTestClient(t, []testAPIResponse{
		sheerWorktreeListResponse(repo),
		sheerMainWorkspaceListResponse(repo),
		sheerWorktreeCreatedResponse("drew/bottom"),
		sheerPaneListResponse(),
		{Result: map[string]any{"type": "pane_input_sent"}},
	})
	defer stop()

	stubSheerSources(t, sheerSources{
		remoteStacks: []string{`[{"number":7,"pull_requests":[{"head":{"ref":"drew/bottom"}},{"head":{"ref":"drew/top"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/bottom\nabc\trefs/heads/drew/top\n",
	})

	if err := client.sheerWorkspaceBranch("drew/bottom", fetchFresh); err != nil {
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
	if want := sheerSetupCommand("drew/bottom"); run.Params["text"] != want {
		t.Fatalf("setup command = %#v, want %q", run.Params["text"], want)
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
		sheerMainWorkspaceListResponse("/tmp/sheer"),
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

	// Without scripting, the stub git exits 0 with empty output, so config
	// --get reports upstream tracking that must be cleared.
	gitCalls := stubGit(t, "")

	if err := client.createSheerWorkspace(sheerWorktreeRequest{Branch: "drew/feature-name"}, io.Discard); err != nil {
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
	wantSetup := sheerSetupCommand("drew/feature-name")
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
		sheerMainWorkspaceListResponse("/tmp/sheer"),
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

	if err := client.createSheerWorkspace(sheerWorktreeRequest{Branch: "drew/feature-name"}, io.Discard); err != nil {
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

func TestCreateSheerWorktreeReusesExistingUpstreamBranch(t *testing.T) {
	client, requests, stop := newTestClient(t, []testAPIResponse{
		sheerMainWorkspaceListResponse("/tmp/sheer"),
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

	// The branch already exists upstream, so it must be reused instead of
	// recreated from main.
	gitCalls := stubGit(t, "")

	request := sheerWorktreeRequest{Branch: "drew/feature-name", Remote: true}
	if err := client.createSheerWorkspace(request, io.Discard); err != nil {
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

func TestCreateSheerWorktreeChecksOutExistingLocalBranch(t *testing.T) {
	client, requests, stop := newTestClient(t, []testAPIResponse{
		sheerMainWorkspaceListResponse("/tmp/sheer"),
		sheerWorktreeCreatedResponse("drew/feature-name"),
		sheerPaneListResponse(),
		{Result: map[string]any{"type": "pane_input_sent"}},
	})
	defer stop()

	useSheerRepo(t, "/tmp/sheer")
	gitCalls := stubGit(t, "")

	request := sheerWorktreeRequest{Branch: "drew/feature-name", Local: true}
	if err := client.createSheerWorkspace(request, io.Discard); err != nil {
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

func TestSheerSetupCommandChecksOutStackBeforeInit(t *testing.T) {
	want := `let checkout = (gh stack checkout "drew/top" | complete); ` +
		`if $checkout.exit_code == 2 { gh stack init "drew/top" } ` +
		`else { print -n $checkout.stdout; print -n -e $checkout.stderr }; pnpm install`
	if got := sheerSetupCommand("drew/top"); got != want {
		t.Errorf("setup = %q, want %q", got, want)
	}
}

func useSheerRepo(t *testing.T, repo string) {
	t.Helper()
	oldSheerRepo := sheerRepo
	sheerRepo = repo
	t.Cleanup(func() { sheerRepo = oldSheerRepo })
}

// sheerSources is the raw output of each source loadSheerCatalog reads.
// remoteStacks holds one JSON array per Stacks API page.
type sheerSources struct {
	localStacks  string
	localRefs    string
	remoteStacks []string
	originHeads  string
}

// stubSheerSources stubs git and gh so loadSheerCatalog reads sources: the
// gh stack catalog file, for-each-ref, the Stacks API, and ls-remote. It
// also gives each test an empty fetch cache.
func stubSheerSources(t *testing.T, sources sheerSources) func() []string {
	t.Helper()

	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	commonDir := t.TempDir()
	if sources.localStacks != "" {
		if err := os.WriteFile(filepath.Join(commonDir, sheerStackCatalog), []byte(sources.localStacks), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("STUB_COMMON_DIR", commonDir)
	t.Setenv("STUB_LOCAL_REFS", sources.localRefs)
	t.Setenv("STUB_ORIGIN_HEADS", sources.originHeads)
	gitCalls := stubGit(t, "case \"$*\" in\n"+
		"*rev-parse*) printf '%s\\n' \"$STUB_COMMON_DIR\" ;;\n"+
		"*for-each-ref*) printf '%b' \"$STUB_LOCAL_REFS\" ;;\n"+
		"*ls-remote*) printf '%b' \"$STUB_ORIGIN_HEADS\" ;;\n"+
		"esac\n")
	stubGitHubStacks(t, sources.remoteStacks...)
	return gitCalls
}

// stubGitHubStacks puts a gh on PATH that serves pages as the Stacks API
// would through gh api --include, and returns its recorded argument lines.
// Each page's ETag is derived from its content, and a request whose
// If-None-Match matches it gets 304 Not Modified, exiting 1 like gh does.
// Pages past the last are empty. The script uses only shell builtins because
// stubGit leaves nothing else on PATH. Call it again to change the pages.
func stubGitHubStacks(t *testing.T, pages ...string) func() []string {
	t.Helper()

	for index, page := range pages {
		t.Setenv(fmt.Sprintf("STUB_PAGE_%d", index+1), page)
		t.Setenv(fmt.Sprintf("STUB_ETAG_%d", index+1), testETag(page))
	}
	t.Setenv("STUB_PAGE_COUNT", strconv.Itoa(len(pages)))
	ghLog := filepath.Join(t.TempDir(), "gh.log")
	t.Setenv("GH_LOG", ghLog)

	binDir := t.TempDir()
	script := `#!/bin/sh
printf '%s\n' "$*" >> "$GH_LOG"
page=
for arg in "$@"; do
	case "$arg" in *page=*) page=${arg##*page=} ;; esac
done
body='[]'
etag='W/"empty"'
if [ "$page" -le "$STUB_PAGE_COUNT" ]; then
	eval "body=\$STUB_PAGE_$page"
	eval "etag=\$STUB_ETAG_$page"
fi
case "$*" in *"If-None-Match: $etag"*)
	printf 'HTTP/2.0 304 Not Modified\nEtag: %s\r\n\r\n' "$etag"
	printf 'gh: HTTP 304\n' >&2
	exit 1
esac
printf 'HTTP/2.0 200 OK\nEtag: %s\r\nX-Ratelimit-Used: 1\r\n\r\n%s' "$etag" "$body"
`
	if err := os.WriteFile(filepath.Join(binDir, "gh"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	return func() []string {
		t.Helper()
		calls, err := os.ReadFile(ghLog)
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		if err != nil {
			t.Fatal(err)
		}
		return strings.Split(strings.TrimSuffix(string(calls), "\n"), "\n")
	}
}

// testETag returns the weak ETag the gh stub serves for a page body.
func testETag(page string) string {
	sum := sha256.Sum256([]byte(page))
	return `W/"` + hex.EncodeToString(sum[:8]) + `"`
}

func sheerWorktreeListResponse(repo string, worktrees ...map[string]any) testAPIResponse {
	list := []any{map[string]any{
		"branch":             "main",
		"is_linked_worktree": false,
		"path":               repo,
	}}
	for _, worktree := range worktrees {
		list = append(list, worktree)
	}
	return testAPIResponse{Result: map[string]any{"type": "worktree_list", "worktrees": list}}
}

func sheerWorktreeCreatedResponse(branch string) testAPIResponse {
	return testAPIResponse{Result: map[string]any{
		"type": "worktree_created",
		"worktree": map[string]any{
			"branch":            branch,
			"label":             sheerBranchLabel(branch),
			"open_workspace_id": "w2",
			"path":              "/tmp/worktrees/sheer/" + strings.ReplaceAll(branch, "/", "-"),
		},
	}}
}

func sheerPaneListResponse() testAPIResponse {
	return testAPIResponse{Result: map[string]any{
		"type": "pane_list",
		"panes": []any{
			map[string]any{
				"pane_id":      "w2:p1",
				"tab_id":       "w2:t1",
				"workspace_id": "w2",
			},
		},
	}}
}

func sheerMainWorkspaceListResponse(repo string) testAPIResponse {
	return testAPIResponse{Result: map[string]any{
		"type": "workspace_list",
		"workspaces": []any{
			map[string]any{
				"workspace_id": "w-main",
				"label":        "sheer",
				"worktree": map[string]any{
					"checkout_path":      repo,
					"is_linked_worktree": false,
					"repo_key":           repo + "/.git",
					"repo_name":          "sheer",
					"repo_root":          repo,
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
	// Only shell builtins, since stubGit can leave nothing else on PATH.
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$FZF_ARGS\"\n" +
		"while IFS= read -r line; do printf '%s\\n' \"$line\"; done > \"$FZF_INPUT\"\n" +
		"printf '%s' \"$FZF_OUTPUT\"\nexit \"$FZF_STATUS\"\n"
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
