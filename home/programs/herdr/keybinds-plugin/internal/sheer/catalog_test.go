package sheer

import (
	"reflect"
	"testing"

	"herdr-keybinds/internal/herdr"
)

func TestBuildEntriesSeparatesStacksFromBranches(t *testing.T) {
	worktrees := []herdr.Worktree{
		{Branch: "drew/local-bottom", Path: "/wt/local"},
		{Branch: "drew/loose", Path: "/wt/loose"},
	}
	local := []catalogEntry{
		{Kind: entryStack, Number: 7, Local: true, Branches: []stackLayer{
			{Name: "drew/shared-bottom"},
			{Name: "drew/shared-unpushed"},
		}},
		{Kind: entryStack, Local: true, Branches: []stackLayer{
			{Name: "drew/local-bottom"},
			{Name: "drew/local-top"},
		}},
	}
	remote := []catalogEntry{
		{Kind: entryStack, Number: 7, Remote: true, Branches: []stackLayer{
			{Name: "drew/shared-bottom", Merged: true},
		}},
		{Kind: entryStack, Number: 9, Remote: true, Branches: []stackLayer{
			{Name: "other/remote-bottom"},
			{Name: "other/remote-top"},
		}},
		{Kind: entryStack, Number: 3, Remote: true, Branches: []stackLayer{
			{Name: "drew/landed", Merged: true},
		}},
	}
	refs := branchRefs{
		local: map[string]bool{
			"main": true, "drew/local-bottom": true, "drew/local-top": true,
			"drew/shared-unpushed": true, "drew/loose": true,
		},
		remote: map[string]bool{
			"HEAD": true, "main": true, "drew/shared-bottom": true,
			"other/remote-bottom": true, "other/remote-top": true, "drew/loose": true, "drew/old": true,
		},
		updated: map[string]int64{
			"drew/local-top": 50, "drew/shared-unpushed": 40, "other/remote-top": 30,
			"drew/loose": 20, "drew/old": 10,
		},
	}

	catalog := branchCatalog{
		choices:   buildEntries(worktrees, local, remote, refs),
		worktrees: worktrees,
		refs:      refs,
	}
	var got []string
	for _, choice := range catalog.visible() {
		got = append(got, choice.line(false))
	}
	want := []string{
		"stack           local         drew/local-bottom <- drew/local-top  [worktree]",
		"stack   #7      local+remote  drew/shared-unpushed",
		"stack   #9      remote        other/remote-bottom <- other/remote-top",
		"branch          local+remote  drew/loose  [worktree]",
		"branch          remote        drew/old",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("visible choices:\n%q\nwant:\n%q", got, want)
	}

	for _, test := range []struct {
		branch   string
		kind     entryKind
		target   string
		worktree string
	}{
		{branch: "drew/local-top", kind: entryStack, target: "drew/local-top", worktree: "/wt/local"},
		{branch: "other/remote-bottom", kind: entryStack, target: "other/remote-top"},
		{branch: "drew/shared-bottom", kind: entryStack, target: "drew/shared-unpushed"},
		{branch: "drew/landed", kind: entryStack, target: "drew/landed"},
		{branch: "drew/loose", kind: entryBranch, target: "drew/loose", worktree: "/wt/loose"},
		{branch: "drew/brand-new", kind: entryBranch, target: "drew/brand-new"},
	} {
		t.Run(test.branch, func(t *testing.T) {
			choice := catalog.find(test.branch)
			if choice.Kind != test.kind || choice.Branch != test.target {
				t.Fatalf("find() = %s %q, want %s %q", choice.Kind, choice.Branch, test.kind, test.target)
			}
			worktree, ok := catalog.worktreeFor(test.branch, choice)
			if ok != (test.worktree != "") || worktree.Path != test.worktree {
				t.Fatalf("worktreeFor() = %q, %v, want %q", worktree.Path, ok, test.worktree)
			}
		})
	}
}

func TestStackWorktreePrefersTargetLayer(t *testing.T) {
	stack := catalogEntry{Kind: entryStack, Branch: "drew/top", Branches: []stackLayer{
		{Name: "drew/bottom"},
		{Name: "drew/top"},
	}}
	worktrees := []herdr.Worktree{
		{Branch: "drew/bottom", Path: "/wt/bottom"},
		{Branch: "drew/top", Path: "/wt/top"},
	}
	if got := stackWorktree(worktrees, stack); got == nil || got.Path != "/wt/top" {
		t.Fatalf("stackWorktree() = %#v, want /wt/top", got)
	}
}

func TestEntryLine(t *testing.T) {
	stack := catalogEntry{
		Kind:   entryStack,
		Branch: "drew/top",
		Number: 29891,
		Branches: []stackLayer{
			{Name: "drew/merged", Merged: true},
			{Name: "drew/bottom"},
			{Name: "drew/top"},
		},
		Local:    true,
		Remote:   true,
		Worktree: &herdr.Worktree{Branch: "drew/bottom"},
	}
	if got, want := stack.line(false), "stack   #29891  local+remote  drew/bottom <- drew/top  [worktree]"; got != want {
		t.Errorf("stack line = %q, want %q", got, want)
	}
	branch := catalogEntry{Kind: entryBranch, Branch: "drew/feature", Remote: true}
	if got, want := branch.line(false), "branch          remote        drew/feature"; got != want {
		t.Errorf("branch line = %q, want %q", got, want)
	}
}
