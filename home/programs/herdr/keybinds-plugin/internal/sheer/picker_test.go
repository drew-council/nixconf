package sheer

import (
	"bytes"
	"io"
	"os"
	"strings"
	"testing"
	"time"

	"herdr-keybinds/internal/fetchcache"
	"herdr-keybinds/internal/herdr"
	"herdr-keybinds/internal/herdr/herdrtest"
)

func TestNormalizeBranchName(t *testing.T) {
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
			if got := normalizeBranchName(test.input); got != test.want {
				t.Fatalf("normalizeBranchName() = %q, want %q", got, test.want)
			}
		})
	}
}

func TestChooseBranchShowsKindsAndAcceptsSelection(t *testing.T) {
	choices := []catalogEntry{
		{
			Kind:   entryStack,
			Branch: "drew/top",
			Number: 7,
			Branches: []stackLayer{
				{Name: "drew/merged", Merged: true},
				{Name: "drew/bottom"},
				{Name: "drew/top"},
			},
			Local:  true,
			Remote: true,
		},
		{Kind: entryBranch, Branch: "drew/existing", Local: true, Worktree: &herdr.Worktree{Branch: "drew/existing"}},
	}
	fzf, inputPath, argsPath := stubFzf(t, "drew/\ndrew/top\t"+choices[0].line(true)+"\n", 0)

	branch, err := chooseBranch(fzf, choices, "")
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

func TestChooseBranchAcceptsNewTypedBranch(t *testing.T) {
	fzf, _, _ := stubFzf(t, "drew/new-branch\ndrew/new-branch\n", 0)

	branch, err := chooseBranch(fzf, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	if branch != "drew/new-branch" {
		t.Fatalf("selected branch = %q, want drew/new-branch", branch)
	}
}

func TestPickOpensStackWorktreeOnAnotherLayer(t *testing.T) {
	// gh resolves the repository from its working directory, so the
	// catalog tests need a checkout path that exists.
	root := t.TempDir()
	client, requests, stop := herdrtest.NewServer(t, []herdrtest.Response{
		worktreeListResponse(root, map[string]any{
			"branch":             "drew/bottom",
			"is_linked_worktree": true,
			"path":               "/tmp/worktrees/sheer/drew-bottom",
		}),
		mainWorkspaceListResponse(root),
		{Result: map[string]any{"type": "worktree_opened"}},
	})
	defer stop()
	r := testRepo(t, client, root)

	stubSources(t, fakeSources{
		localStacks:  `{"stacks":[{"number":7,"branches":[{"branch":"drew/bottom"},{"branch":"drew/top"}]}]}`,
		localRefs:    "refs/heads/drew/bottom\t20\nrefs/heads/drew/top\t30\n",
		remoteStacks: []string{`[{"number":7,"pull_requests":[{"head":{"ref":"drew/bottom"}},{"head":{"ref":"drew/top"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/bottom\nabc\trefs/heads/drew/top\n",
	})
	fzf, _, _ := stubFzf(t, "drew/\ndrew/top\tstack\n", 0)

	if err := r.pick(fzf, fetchcache.Fresh); err != nil {
		t.Fatal(err)
	}
	if len(*requests) != 3 {
		t.Fatalf("captured %d requests, want 3", len(*requests))
	}
	if request := (*requests)[0]; request.Method != "worktree.list" || request.Params["cwd"] != root {
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

func TestPickShowsStaleCacheAndReloads(t *testing.T) {
	root := t.TempDir()
	client, requests, stop := herdrtest.NewServer(t, []herdrtest.Response{
		worktreeListResponse(root),
		worktreeListResponse(root),
		worktreeListResponse(root, map[string]any{
			"branch":             "drew/top",
			"is_linked_worktree": true,
			"path":               "/tmp/worktrees/sheer/drew-top",
		}),
		mainWorkspaceListResponse(root),
		{Result: map[string]any{"type": "worktree_opened"}},
	})
	defer stop()
	r := testRepo(t, client, root)

	// Cache what GitHub and origin looked like an hour ago.
	stubSources(t, fakeSources{
		remoteStacks: []string{`[{"number":3,"pull_requests":[{"head":{"ref":"drew/old"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/old\n",
	})
	r.cache.Now = func() time.Time { return time.Now().Add(-time.Hour) }
	if err := r.list(io.Discard, listText, fetchcache.Fresh); err != nil {
		t.Fatal(err)
	}
	r.cache.Now = time.Now

	stubSources(t, fakeSources{
		remoteStacks: []string{`[{"number":7,"pull_requests":[{"head":{"ref":"drew/bottom"}},{"head":{"ref":"drew/top"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/bottom\nabc\trefs/heads/drew/top\n",
	})
	ghCalls := stubGitHubStacks(t, `[{"number":7,"pull_requests":[{"head":{"ref":"drew/bottom"}},{"head":{"ref":"drew/top"}}]}]`)
	fzf, inputPath, argsPath := stubFzf(t, "drew/\ndrew/top\tstack\n", 0)

	if err := r.pick(fzf, fetchcache.Fresh); err != nil {
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
	if open := (*requests)[4]; open.Method != "worktree.open" || open.Params["path"] != "/tmp/worktrees/sheer/drew-top" {
		t.Fatalf("open request = %#v, want the drew/top worktree", open)
	}
}

func TestListUsesCacheWithinTTL(t *testing.T) {
	root := t.TempDir()
	client, _, stop := herdrtest.NewServer(t, []herdrtest.Response{
		worktreeListResponse(root),
		worktreeListResponse(root),
		worktreeListResponse(root),
	})
	defer stop()
	r := testRepo(t, client, root)

	gitCalls := stubSources(t, fakeSources{
		remoteStacks: []string{`[{"number":7,"pull_requests":[{"head":{"ref":"drew/top"}}]}]`},
		originHeads:  "abc\trefs/heads/drew/top\n",
	})
	ghCalls := stubGitHubStacks(t, `[{"number":7,"pull_requests":[{"head":{"ref":"drew/top"}}]}]`)

	var first, second bytes.Buffer
	if err := r.list(&first, listText, fetchcache.Fresh); err != nil {
		t.Fatal(err)
	}
	if err := r.list(&second, listText, fetchcache.Fresh); err != nil {
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

	if err := r.list(io.Discard, listText, fetchcache.Refresh); err != nil {
		t.Fatal(err)
	}
	if got := ghCalls(); len(got) != 2 || !strings.Contains(got[1], "If-None-Match") {
		t.Fatalf("gh calls after --refresh = %q, want a conditional request", got)
	}
	if got := countLsRemote(); got != 2 {
		t.Fatalf("ls-remote ran %d times after --refresh, want 2", got)
	}
}
