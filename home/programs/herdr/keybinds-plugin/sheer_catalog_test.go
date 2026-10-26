package main

import (
	"reflect"
	"testing"
)

func TestBuildSheerChoicesSeparatesStacksFromBranches(t *testing.T) {
	worktrees := []existingWorktreeInfo{
		{Branch: "drew/local-bottom", Path: "/wt/local"},
		{Branch: "drew/loose", Path: "/wt/loose"},
	}
	local := []sheerChoice{
		{Kind: sheerChoiceStack, Number: 7, Local: true, Branches: []sheerStackBranch{
			{Name: "drew/shared-bottom"},
			{Name: "drew/shared-unpushed"},
		}},
		{Kind: sheerChoiceStack, Local: true, Branches: []sheerStackBranch{
			{Name: "drew/local-bottom"},
			{Name: "drew/local-top"},
		}},
	}
	remote := []sheerChoice{
		{Kind: sheerChoiceStack, Number: 7, Remote: true, Branches: []sheerStackBranch{
			{Name: "drew/shared-bottom", Merged: true},
		}},
		{Kind: sheerChoiceStack, Number: 9, Remote: true, Branches: []sheerStackBranch{
			{Name: "other/remote-bottom"},
			{Name: "other/remote-top"},
		}},
		{Kind: sheerChoiceStack, Number: 3, Remote: true, Branches: []sheerStackBranch{
			{Name: "drew/landed", Merged: true},
		}},
	}
	refs := sheerBranchRefs{
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

	catalog := sheerCatalog{
		choices:   buildSheerChoices(worktrees, local, remote, refs),
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
		kind     sheerChoiceKind
		target   string
		worktree string
	}{
		{branch: "drew/local-top", kind: sheerChoiceStack, target: "drew/local-top", worktree: "/wt/local"},
		{branch: "other/remote-bottom", kind: sheerChoiceStack, target: "other/remote-top"},
		{branch: "drew/shared-bottom", kind: sheerChoiceStack, target: "drew/shared-unpushed"},
		{branch: "drew/landed", kind: sheerChoiceStack, target: "drew/landed"},
		{branch: "drew/loose", kind: sheerChoiceBranch, target: "drew/loose", worktree: "/wt/loose"},
		{branch: "drew/brand-new", kind: sheerChoiceBranch, target: "drew/brand-new"},
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
	stack := sheerChoice{Kind: sheerChoiceStack, Branch: "drew/top", Branches: []sheerStackBranch{
		{Name: "drew/bottom"},
		{Name: "drew/top"},
	}}
	worktrees := []existingWorktreeInfo{
		{Branch: "drew/bottom", Path: "/wt/bottom"},
		{Branch: "drew/top", Path: "/wt/top"},
	}
	if got := stackWorktree(worktrees, stack); got == nil || got.Path != "/wt/top" {
		t.Fatalf("stackWorktree() = %#v, want /wt/top", got)
	}
}

func TestParseLocalSheerStacks(t *testing.T) {
	stacks, err := parseLocalSheerStacks([]byte(`{
		"schemaVersion": 1,
		"stacks": [
			{"id": "1", "number": 27930, "trunk": {"branch": "main"}, "branches": [
				{"branch": "drew/a", "pullRequest": {"number": 1, "merged": true}},
				{"branch": "drew/b", "pullRequest": {"number": 2}},
				{"branch": "drew/c"}
			]},
			{"trunk": {"branch": "main"}, "branches": []}
		]
	}`))
	if err != nil {
		t.Fatal(err)
	}
	want := []sheerChoice{{
		Kind:   sheerChoiceStack,
		Number: 27930,
		Local:  true,
		Branches: []sheerStackBranch{
			{Name: "drew/a", Merged: true},
			{Name: "drew/b"},
			{Name: "drew/c"},
		},
	}}
	if !reflect.DeepEqual(stacks, want) {
		t.Fatalf("stacks = %#v, want %#v", stacks, want)
	}
}

func TestParseRemoteSheerStacks(t *testing.T) {
	stacks, err := parseRemoteSheerStacks([]byte(`[
		[{"number": 30033, "pull_requests": [
			{"number": 1, "merged_at": "2026-10-01T00:00:00Z", "head": {"ref": "drew/a"}},
			{"number": 2, "merged_at": null, "head": {"ref": "drew/b"}}
		]}],
		[{"number": 0, "pull_requests": [{"head": {"ref": "ignored"}}]}, {"number": 5, "pull_requests": []}]
	]`))
	if err != nil {
		t.Fatal(err)
	}
	want := []sheerChoice{{
		Kind:   sheerChoiceStack,
		Number: 30033,
		Remote: true,
		Branches: []sheerStackBranch{
			{Name: "drew/a", Merged: true},
			{Name: "drew/b"},
		},
	}}
	if !reflect.DeepEqual(stacks, want) {
		t.Fatalf("stacks = %#v, want %#v", stacks, want)
	}
}
