package main

import (
	"bufio"
	"bytes"
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
)

const (
	sheerTrunkBranch    = "main"
	sheerStackCatalog   = "gh-stack"
	sheerRemoteRefsBase = "refs/remotes/origin/"
	sheerLocalRefsBase  = "refs/heads/"
	githubStacksPerPage = 100
)

// sheerChoiceKind separates gh stacks from branches that belong to none, so
// the picker and list can present them as distinct options.
type sheerChoiceKind string

const (
	sheerChoiceStack  sheerChoiceKind = "stack"
	sheerChoiceBranch sheerChoiceKind = "branch"
)

// sheerStackBranch is one layer of a stack, bottom to top.
type sheerStackBranch struct {
	Name   string `json:"name"`
	Merged bool   `json:"merged"`
}

// sheerChoice is one stack or unstacked branch a sheer workspace can be
// opened on. Branch is the name to pass to --branch; for stacks it is the
// top unmerged layer, which is also what gh stack checks out by default.
type sheerChoice struct {
	Kind     sheerChoiceKind       `json:"kind"`
	Branch   string                `json:"branch"`
	Number   int                   `json:"number,omitempty"`
	Branches []sheerStackBranch    `json:"branches,omitempty"`
	Local    bool                  `json:"local"`
	Remote   bool                  `json:"remote"`
	Worktree *existingWorktreeInfo `json:"worktree,omitempty"`

	updated int64
}

// fullyMerged reports whether a stack has nothing left to work on, matching
// gh stack checkout's picker, which hides such stacks.
func (choice sheerChoice) fullyMerged() bool {
	if choice.Kind != sheerChoiceStack {
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
func (choice sheerChoice) contains(branch string) bool {
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
func (choice sheerChoice) line(color bool) string {
	paint := func(code string, text string) string {
		if !color || text == "" {
			return text
		}
		return "\x1b[" + code + "m" + text + "\x1b[0m"
	}

	kindColor, number, name := "34", "", choice.Branch
	if choice.Kind == sheerChoiceStack {
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

// sheerBranchRefs records which branch names exist locally and on origin,
// with commit times used to list recently touched work first.
type sheerBranchRefs struct {
	local   map[string]bool
	remote  map[string]bool
	updated map[string]int64
}

// sheerCatalog is every stack and unstacked branch in the sheer repo, along
// with the worktrees that already have one of them checked out.
type sheerCatalog struct {
	choices   []sheerChoice
	worktrees []existingWorktreeInfo
	refs      sheerBranchRefs
	// stale is set when GitHub or origin data came from a cache entry older
	// than fetchCacheTTL, which only fetchStale returns without refetching.
	stale bool
}

// visible returns the choices worth offering, omitting fully merged stacks.
func (catalog sheerCatalog) visible() []sheerChoice {
	choices := make([]sheerChoice, 0, len(catalog.choices))
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
func (catalog sheerCatalog) find(branch string) sheerChoice {
	var merged *sheerChoice
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
	return sheerChoice{Kind: sheerChoiceBranch, Branch: branch}
}

// worktreeFor returns the worktree to open for branch: one with that exact
// branch checked out, or else one on another layer of the same stack, since
// a stack is worked on from a single worktree that moves between layers.
func (catalog sheerCatalog) worktreeFor(branch string, choice sheerChoice) (existingWorktreeInfo, bool) {
	for _, worktree := range catalog.worktrees {
		if worktree.Branch == branch {
			return worktree, true
		}
	}
	if choice.Kind == sheerChoiceStack && choice.Worktree != nil {
		return *choice.Worktree, true
	}
	return existingWorktreeInfo{}, false
}

// loadSheerCatalog gathers worktrees, stacks, and branches for the canonical
// sheer checkout. GitHub and origin lookups go through the fetch cache
// according to mode and run concurrently because they dominate the latency;
// failures there degrade to cached or local data with a warning.
func (c *client) loadSheerCatalog(warnings io.Writer, mode fetchMode) (sheerCatalog, error) {
	if sheerRepo == "" {
		return sheerCatalog{}, errors.New("sheer repository path is not configured")
	}
	cache, err := newFetchCache(sheerRepo)
	if err != nil {
		return sheerCatalog{}, err
	}

	var (
		wait         sync.WaitGroup
		stackPages   []githubStackPage
		stacksStale  bool
		remoteErr    error
		originHeads  map[string]bool
		originsStale bool
		originErr    error
	)
	wait.Go(func() {
		stackPages, stacksStale, remoteErr = cachedFetch(cache, "github-stacks", mode, warnings,
			func(previous *[]githubStackPage) ([]githubStackPage, error) {
				if previous == nil {
					return fetchGitHubStackPages(sheerRepo, nil)
				}
				return fetchGitHubStackPages(sheerRepo, *previous)
			})
	})
	wait.Go(func() {
		originHeads, originsStale, originErr = cachedFetch(cache, "origin-heads", mode, warnings,
			func(*map[string]bool) (map[string]bool, error) { return originBranchHeads(sheerRepo) })
	})

	worktrees, err := c.sheerWorktrees()
	if err != nil {
		wait.Wait()
		return sheerCatalog{}, err
	}
	localStacks, err := localSheerStacks(sheerRepo)
	if err != nil {
		wait.Wait()
		return sheerCatalog{}, err
	}
	refs, err := sheerRefs(sheerRepo)
	if err != nil {
		wait.Wait()
		return sheerCatalog{}, err
	}
	wait.Wait()

	remoteStacks, err := parseRemoteSheerStacks(stackPages)
	if remoteErr == nil && err != nil {
		remoteErr = err
	}
	if remoteErr != nil {
		fmt.Fprintf(warnings, "warning: listing GitHub stacks failed, showing local stacks only: %v\n", remoteErr)
	}
	if originErr != nil {
		fmt.Fprintf(warnings, "warning: listing origin branches failed, using remote-tracking refs: %v\n", originErr)
	} else {
		refs.remote = originHeads
	}

	return sheerCatalog{
		choices:   buildSheerChoices(worktrees, localStacks, remoteStacks, refs),
		worktrees: worktrees,
		refs:      refs,
		stale:     stacksStale || originsStale,
	}, nil
}

// buildSheerChoices merges local and GitHub stacks by stack number, then adds
// every remaining local or origin branch as an unstacked choice. Stacks come
// first, and each group lists the most recently committed work first.
func buildSheerChoices(
	worktrees []existingWorktreeInfo,
	localStacks []sheerChoice,
	remoteStacks []sheerChoice,
	refs sheerBranchRefs,
) []sheerChoice {
	remoteByNumber := make(map[int]int, len(remoteStacks))
	for index, stack := range remoteStacks {
		remoteByNumber[stack.Number] = index
	}

	matched := make(map[int]bool, len(remoteStacks))
	stacks := make([]sheerChoice, 0, len(localStacks)+len(remoteStacks))
	for _, stack := range localStacks {
		if index, ok := remoteByNumber[stack.Number]; ok && stack.Number != 0 {
			matched[index] = true
			stack = mergeSheerStacks(stack, remoteStacks[index])
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
	branches := make([]sheerChoice, 0, len(names))
	for name := range names {
		if name == sheerTrunkBranch || name == "HEAD" || stacked[name] {
			continue
		}
		choice := sheerChoice{
			Kind:    sheerChoiceBranch,
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

	sortSheerChoices(stacks)
	sortSheerChoices(branches)
	return append(stacks, branches...)
}

// mergeSheerStacks keeps the local layers, which may include unpushed
// branches, while folding in merge state that GitHub knows about first.
func mergeSheerStacks(local sheerChoice, remote sheerChoice) sheerChoice {
	merged := make(map[string]bool, len(remote.Branches))
	for _, layer := range remote.Branches {
		merged[layer.Name] = layer.Merged
	}
	local.Remote = true
	local.Branches = append([]sheerStackBranch(nil), local.Branches...)
	for index := range local.Branches {
		local.Branches[index].Merged = local.Branches[index].Merged || merged[local.Branches[index].Name]
	}
	return local
}

// topUnmergedLayer returns the highest unmerged layer, falling back to the
// top layer of a fully merged stack.
func topUnmergedLayer(layers []sheerStackBranch) string {
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
func stackWorktree(worktrees []existingWorktreeInfo, stack sheerChoice) *existingWorktreeInfo {
	var found *existingWorktreeInfo
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

// sortSheerChoices orders choices by most recent commit, then by name.
func sortSheerChoices(choices []sheerChoice) {
	sort.SliceStable(choices, func(i, j int) bool {
		if choices[i].updated != choices[j].updated {
			return choices[i].updated > choices[j].updated
		}
		return choices[i].Branch < choices[j].Branch
	})
}

// localSheerStacks reads gh stack's catalog from the repository's common Git
// directory. gh stack has no listing command, so this mirrors the fields its
// own checkout picker reads from the same file.
func localSheerStacks(repo string) ([]sheerChoice, error) {
	output, err := exec.Command("git", "-C", repo, "rev-parse", "--path-format=absolute", "--git-common-dir").Output()
	if err != nil {
		return nil, fmt.Errorf("find git common dir for %s: %w", repo, err)
	}
	path := filepath.Join(strings.TrimSpace(string(output)), sheerStackCatalog)
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	return parseLocalSheerStacks(data)
}

// parseLocalSheerStacks decodes gh stack's local catalog file.
func parseLocalSheerStacks(data []byte) ([]sheerChoice, error) {
	var catalog struct {
		Stacks []struct {
			Number   int `json:"number"`
			Branches []struct {
				Branch      string `json:"branch"`
				PullRequest *struct {
					Merged bool `json:"merged"`
				} `json:"pullRequest"`
			} `json:"branches"`
		} `json:"stacks"`
	}
	if err := json.Unmarshal(data, &catalog); err != nil {
		return nil, fmt.Errorf("parse gh stack catalog: %w", err)
	}

	stacks := make([]sheerChoice, 0, len(catalog.Stacks))
	for _, stack := range catalog.Stacks {
		if len(stack.Branches) == 0 {
			continue
		}
		choice := sheerChoice{Kind: sheerChoiceStack, Number: stack.Number, Local: true}
		for _, branch := range stack.Branches {
			choice.Branches = append(choice.Branches, sheerStackBranch{
				Name:   branch.Branch,
				Merged: branch.PullRequest != nil && branch.PullRequest.Merged,
			})
		}
		stacks = append(stacks, choice)
	}
	return stacks, nil
}

// githubStackPage is one page of the Stacks API, kept with the ETag that
// lets a later request revalidate it.
type githubStackPage struct {
	ETag string          `json:"etag,omitempty"`
	Body json.RawMessage `json:"body"`
}

// fetchGitHubStackPages lists the repository's stacks from GitHub's Stacks
// REST API, the same endpoint gh stack checkout uses to find remote-only
// stacks. Pages from previous are revalidated by ETag, and GitHub answers
// unchanged ones with 304 Not Modified, which does not count against the rate
// limit. Previously seen pages are requested concurrently; pages beyond them
// are followed one at a time while they come back full.
func fetchGitHubStackPages(repo string, previous []githubStackPage) ([]githubStackPage, error) {
	cachedPage := func(index int) *githubStackPage {
		if index < len(previous) {
			return &previous[index]
		}
		return nil
	}

	pages := make([]githubStackPage, max(len(previous), 1))
	errs := make([]error, len(pages))
	var wait sync.WaitGroup
	for index := range pages {
		wait.Go(func() {
			pages[index], errs[index] = fetchGitHubStackPage(repo, index+1, cachedPage(index))
		})
	}
	wait.Wait()
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}

	// Stacks are listed newest first, so new stacks push older ones onto
	// later pages, and closed ones can shorten the list.
	for index := 0; ; index++ {
		if index == len(pages) {
			page, err := fetchGitHubStackPage(repo, index+1, cachedPage(index))
			if err != nil {
				return nil, err
			}
			pages = append(pages, page)
		}
		var stacks []json.RawMessage
		if err := json.Unmarshal(pages[index].Body, &stacks); err != nil {
			return nil, fmt.Errorf("parse GitHub stacks page %d: %w", index+1, err)
		}
		if len(stacks) < githubStacksPerPage {
			return pages[:index+1], nil
		}
	}
}

// fetchGitHubStackPage requests one page of stacks, sending cached's ETag so
// an unchanged page can be answered with 304 and reused.
func fetchGitHubStackPage(repo string, number int, cached *githubStackPage) (githubStackPage, error) {
	args := []string{
		"api", "--include",
		fmt.Sprintf("repos/{owner}/{repo}/stacks?per_page=%d&page=%d", githubStacksPerPage, number),
	}
	if cached != nil && cached.ETag != "" {
		args = append(args, "--header", "If-None-Match: "+cached.ETag)
	}
	command := exec.Command("gh", args...)
	command.Dir = repo
	var stderr bytes.Buffer
	command.Stderr = &stderr
	// gh exits non-zero for 304, so the status line decides the outcome.
	output, runErr := command.Output()
	status, etag, body, parseErr := parseIncludedResponse(output)
	switch {
	case parseErr == nil && status == http.StatusNotModified && cached != nil:
		return *cached, nil
	case parseErr == nil && status == http.StatusOK && runErr == nil:
		return githubStackPage{ETag: etag, Body: body}, nil
	}
	return githubStackPage{}, fmt.Errorf("gh api stacks page %d: %w: %s",
		number, cmp.Or(runErr, parseErr, fmt.Errorf("HTTP %d", status)), strings.TrimSpace(stderr.String()))
}

// parseIncludedResponse splits gh api --include output into its status code,
// ETag header, and body.
func parseIncludedResponse(output []byte) (int, string, []byte, error) {
	head, body, found := bytes.Cut(output, []byte("\r\n\r\n"))
	if !found {
		head, body, found = bytes.Cut(output, []byte("\n\n"))
	}
	if !found {
		return 0, "", nil, errors.New("response has no header terminator")
	}
	lines := strings.Split(string(head), "\n")
	status := strings.Fields(lines[0])
	if len(status) < 2 || !strings.HasPrefix(status[0], "HTTP/") {
		return 0, "", nil, fmt.Errorf("malformed status line %q", lines[0])
	}
	code, err := strconv.Atoi(status[1])
	if err != nil {
		return 0, "", nil, fmt.Errorf("malformed status line %q", lines[0])
	}
	etag := ""
	for _, line := range lines[1:] {
		name, value, ok := strings.Cut(strings.TrimRight(line, "\r"), ":")
		if ok && strings.EqualFold(strings.TrimSpace(name), "etag") {
			etag = strings.TrimSpace(value)
		}
	}
	return code, etag, body, nil
}

// parseRemoteSheerStacks decodes cached Stacks API pages.
func parseRemoteSheerStacks(pages []githubStackPage) ([]sheerChoice, error) {
	var stacks []sheerChoice
	for index, page := range pages {
		var entries []struct {
			Number       int `json:"number"`
			PullRequests []struct {
				MergedAt *string `json:"merged_at"`
				Head     struct {
					Ref string `json:"ref"`
				} `json:"head"`
			} `json:"pull_requests"`
		}
		if err := json.Unmarshal(page.Body, &entries); err != nil {
			return nil, fmt.Errorf("parse GitHub stacks page %d: %w", index+1, err)
		}
		for _, stack := range entries {
			if stack.Number <= 0 || len(stack.PullRequests) == 0 {
				continue
			}
			choice := sheerChoice{Kind: sheerChoiceStack, Number: stack.Number, Remote: true}
			for _, pr := range stack.PullRequests {
				choice.Branches = append(choice.Branches, sheerStackBranch{
					Name:   pr.Head.Ref,
					Merged: pr.MergedAt != nil && *pr.MergedAt != "",
				})
			}
			stacks = append(stacks, choice)
		}
	}
	return stacks, nil
}

// sheerRefs reads local branches and origin's remote-tracking branches with
// their commit times. Remote-tracking refs can be stale, so loadSheerCatalog
// replaces the remote set with origin's live heads when it can reach origin.
func sheerRefs(repo string) (sheerBranchRefs, error) {
	output, err := exec.Command(
		"git", "-C", repo, "for-each-ref",
		"--format=%(refname)%09%(committerdate:unix)",
		sheerLocalRefsBase, sheerRemoteRefsBase,
	).Output()
	if err != nil {
		return sheerBranchRefs{}, fmt.Errorf("list branches in %s: %w", repo, err)
	}

	refs := sheerBranchRefs{
		local:   make(map[string]bool),
		remote:  make(map[string]bool),
		updated: make(map[string]int64),
	}
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		ref, timestamp, _ := strings.Cut(scanner.Text(), "\t")
		var name string
		if local, ok := strings.CutPrefix(ref, sheerLocalRefsBase); ok {
			name = local
			refs.local[name] = true
		} else if remote, ok := strings.CutPrefix(ref, sheerRemoteRefsBase); ok {
			name = remote
			refs.remote[name] = true
		} else {
			continue
		}
		updated, _ := strconv.ParseInt(timestamp, 10, 64)
		refs.updated[name] = max(refs.updated[name], updated)
	}
	return refs, nil
}

// originBranchHeads lists branch names currently on origin.
func originBranchHeads(repo string) (map[string]bool, error) {
	output, err := exec.Command("git", "-C", repo, "ls-remote", "--heads", "origin").Output()
	if err != nil {
		return nil, fmt.Errorf("git ls-remote origin: %w", err)
	}
	heads := make(map[string]bool)
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		_, ref, _ := strings.Cut(scanner.Text(), "\t")
		if name, ok := strings.CutPrefix(ref, sheerLocalRefsBase); ok {
			heads[name] = true
		}
	}
	return heads, nil
}
