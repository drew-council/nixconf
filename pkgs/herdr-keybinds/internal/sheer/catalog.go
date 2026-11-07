package sheer

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"herdr-keybinds/internal/herdr"
)

// trunkBranch is the branch stacks are based on, which is never offered as
// a branch of its own.
const trunkBranch = "main"

// entryKind separates gh stacks from branches that belong to none, so
// the picker and list can present them as distinct options.
type entryKind string

const (
	entryStack  entryKind = "stack"
	entryBranch entryKind = "branch"
)

// stackLayer is one layer of a stack, bottom to top.
type stackLayer struct {
	Name   string `json:"name"`
	Merged bool   `json:"merged"`
}

// catalogEntry is one stack or unstacked branch a sheer workspace can be
// opened on. Branch is the name to pass to --branch; for stacks it is the
// top unmerged layer, which is also what gh stack checks out by default.
type catalogEntry struct {
	Kind     entryKind       `json:"kind"`
	Branch   string          `json:"branch"`
	Number   int             `json:"number,omitempty"`
	Branches []stackLayer    `json:"branches,omitempty"`
	Local    bool            `json:"local"`
	Remote   bool            `json:"remote"`
	Worktree *herdr.Worktree `json:"worktree,omitempty"`

	updated int64
}

// fullyMerged reports whether a stack has nothing left to work on, matching
// gh stack checkout's picker, which hides such stacks.
func (choice catalogEntry) fullyMerged() bool {
	if choice.Kind != entryStack {
		return false
	}
	for _, branch := range choice.Branches {
		if !branch.Merged {
			return false
		}
	}
	return true
}

// contains reports whether branch is this choice's branch or a stack layer.
func (choice catalogEntry) contains(branch string) bool {
	if choice.Branch == branch {
		return true
	}
	for _, layer := range choice.Branches {
		if layer.Name == branch {
			return true
		}
	}
	return false
}

// line renders the choice as aligned columns shared by fzf and list output.
// Stacks show their unmerged layers trunk-first, as gh stack prints them.
func (choice catalogEntry) line(color bool) string {
	paint := func(code string, text string) string {
		if !color || text == "" {
			return text
		}
		return "\x1b[" + code + "m" + text + "\x1b[0m"
	}

	kindColor, number, name := "34", "", choice.Branch
	if choice.Kind == entryStack {
		kindColor = "35"
		if choice.Number != 0 {
			number = "#" + strconv.Itoa(choice.Number)
		}
		layers := make([]string, 0, len(choice.Branches))
		for _, layer := range choice.Branches {
			if !layer.Merged {
				layers = append(layers, layer.Name)
			}
		}
		name = strings.Join(layers, " <- ")
	}

	location := "remote"
	switch {
	case choice.Local && choice.Remote:
		location = "local+remote"
	case choice.Local:
		location = "local"
	}

	line := fmt.Sprintf("%s  %s  %-12s  %s",
		paint(kindColor, fmt.Sprintf("%-6s", choice.Kind)),
		paint("2", fmt.Sprintf("%-6s", number)),
		location,
		name,
	)
	if choice.Worktree != nil {
		line += "  " + paint("32", "[worktree]")
	}
	return line
}

// branchRefs records which branch names exist locally and on origin,
// with commit times used to list recently touched work first.
type branchRefs struct {
	local   map[string]bool
	remote  map[string]bool
	updated map[string]int64
}

// branchCatalog is every stack and unstacked branch in the sheer repo, along
// with the worktrees that already have one of them checked out.
type branchCatalog struct {
	choices   []catalogEntry
	worktrees []herdr.Worktree
	refs      branchRefs
	// stale is set when GitHub or origin data came from a cache entry older
	// than fetchcache.TTL, which only fetchcache.Stale returns without refetching.
	stale bool
}

// visible returns the choices worth offering, omitting fully merged stacks.
func (catalog branchCatalog) visible() []catalogEntry {
	choices := make([]catalogEntry, 0, len(catalog.choices))
	for _, choice := range catalog.choices {
		if !choice.fullyMerged() {
			choices = append(choices, choice)
		}
	}
	return choices
}

// find resolves a branch name to its stack, preferring stacks that still
// have open layers, then to an unstacked branch. Unknown names resolve to a
// new branch choice so callers can create it.
func (catalog branchCatalog) find(branch string) catalogEntry {
	var merged *catalogEntry
	for index, choice := range catalog.choices {
		if !choice.contains(branch) {
			continue
		}
		if !choice.fullyMerged() {
			return choice
		}
		if merged == nil {
			merged = &catalog.choices[index]
		}
	}
	if merged != nil {
		return *merged
	}
	return catalogEntry{Kind: entryBranch, Branch: branch}
}

// worktreeFor returns the worktree to open for branch: one with that exact
// branch checked out, or else one on another layer of the same stack, since
// a stack is worked on from a single worktree that moves between layers.
func (catalog branchCatalog) worktreeFor(branch string, choice catalogEntry) (herdr.Worktree, bool) {
	for _, worktree := range catalog.worktrees {
		if worktree.Branch == branch {
			return worktree, true
		}
	}
	if choice.Kind == entryStack && choice.Worktree != nil {
		return *choice.Worktree, true
	}
	return herdr.Worktree{}, false
}

// buildEntries merges local and GitHub stacks by stack number, then adds
// every remaining local or origin branch as an unstacked choice. Stacks come
// first, and each group lists the most recently committed work first.
func buildEntries(
	worktrees []herdr.Worktree,
	localStacks []catalogEntry,
	remoteStacks []catalogEntry,
	refs branchRefs,
) []catalogEntry {
	remoteByNumber := make(map[int]int, len(remoteStacks))
	for index, stack := range remoteStacks {
		remoteByNumber[stack.Number] = index
	}

	matched := make(map[int]bool, len(remoteStacks))
	stacks := make([]catalogEntry, 0, len(localStacks)+len(remoteStacks))
	for _, stack := range localStacks {
		if index, ok := remoteByNumber[stack.Number]; ok && stack.Number != 0 {
			matched[index] = true
			stack = mergeStacks(stack, remoteStacks[index])
		}
		stacks = append(stacks, stack)
	}
	for index, stack := range remoteStacks {
		if !matched[index] {
			stacks = append(stacks, stack)
		}
	}

	stacked := make(map[string]bool)
	for index := range stacks {
		stack := &stacks[index]
		stack.Branch = topUnmergedLayer(stack.Branches)
		for _, layer := range stack.Branches {
			stacked[layer.Name] = true
			stack.updated = max(stack.updated, refs.updated[layer.Name])
		}
		stack.Worktree = stackWorktree(worktrees, *stack)
	}

	names := make(map[string]bool, len(refs.local)+len(refs.remote))
	for name := range refs.local {
		names[name] = true
	}
	for name := range refs.remote {
		names[name] = true
	}
	branches := make([]catalogEntry, 0, len(names))
	for name := range names {
		if name == trunkBranch || name == "HEAD" || stacked[name] {
			continue
		}
		choice := catalogEntry{
			Kind:    entryBranch,
			Branch:  name,
			Local:   refs.local[name],
			Remote:  refs.remote[name],
			updated: refs.updated[name],
		}
		for _, worktree := range worktrees {
			if worktree.Branch == name {
				choice.Worktree = &worktree
				break
			}
		}
		branches = append(branches, choice)
	}

	sortEntries(stacks)
	sortEntries(branches)
	return append(stacks, branches...)
}

// mergeStacks keeps the local layers, which may include unpushed
// branches, while folding in merge state that GitHub knows about first.
func mergeStacks(local catalogEntry, remote catalogEntry) catalogEntry {
	merged := make(map[string]bool, len(remote.Branches))
	for _, layer := range remote.Branches {
		merged[layer.Name] = layer.Merged
	}
	local.Remote = true
	local.Branches = append([]stackLayer(nil), local.Branches...)
	for index := range local.Branches {
		local.Branches[index].Merged = local.Branches[index].Merged || merged[local.Branches[index].Name]
	}
	return local
}

// topUnmergedLayer returns the highest unmerged layer, falling back to the
// top layer of a fully merged stack.
func topUnmergedLayer(layers []stackLayer) string {
	for index := len(layers) - 1; index >= 0; index-- {
		if !layers[index].Merged {
			return layers[index].Name
		}
	}
	if len(layers) == 0 {
		return ""
	}
	return layers[len(layers)-1].Name
}

// stackWorktree finds a worktree on any layer of stack, preferring the layer
// the stack would be opened on.
func stackWorktree(worktrees []herdr.Worktree, stack catalogEntry) *herdr.Worktree {
	var found *herdr.Worktree
	for index := range worktrees {
		worktree := &worktrees[index]
		if worktree.Branch == stack.Branch {
			return worktree
		}
		if found == nil && stack.contains(worktree.Branch) {
			found = worktree
		}
	}
	return found
}

// sortEntries orders choices by most recent commit, then by name.
func sortEntries(choices []catalogEntry) {
	sort.SliceStable(choices, func(i, j int) bool {
		if choices[i].updated != choices[j].updated {
			return choices[i].updated > choices[j].updated
		}
		return choices[i].Branch < choices[j].Branch
	})
}
