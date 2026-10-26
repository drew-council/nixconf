package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	sheerWorkspacePickerEntrypoint = "sheer-workspace-picker"
	sheerBranchPrefix              = "drew/"
	sheerBaseBranch                = "origin/main"
	// herdrWorktreeDirectory is Herdr's default worktrees.directory, relative
	// to $HOME, where it creates managed checkouts.
	herdrWorktreeDirectory = ".herdr/worktrees"
	workspacePaneWait      = 2 * time.Second
	workspacePanePoll      = 50 * time.Millisecond
)

// sheerRepo is injected by Nix from vars.workDir so this action always manages
// worktrees from the canonical checkout rather than whichever workspace is open.
var sheerRepo string

// existingWorktreeInfo is the subset returned by worktree.list needed by the
// sheer workspace picker.
type existingWorktreeInfo struct {
	Branch           string `json:"branch"`
	IsLinkedWorktree bool   `json:"is_linked_worktree"`
	IsPrunable       bool   `json:"is_prunable"`
	OpenWorkspaceID  string `json:"open_workspace_id"`
	Path             string `json:"path"`
}

// createdWorktreeInfo is the subset returned by worktree.create that is needed
// to start setup in the newly created workspace.
type createdWorktreeInfo struct {
	Branch          string `json:"branch"`
	Label           string `json:"label"`
	OpenWorkspaceID string `json:"open_workspace_id"`
	Path            string `json:"path"`
}

// openSheerWorkspacePicker opens the combined sheer worktree picker and creator
// as an overlay.
func (c *client) openSheerWorkspacePicker() error {
	pane, err := c.currentPane()
	if err != nil {
		return err
	}
	_, err = c.openPluginOverlay(sheerWorkspacePickerEntrypoint, activePaneCWD(pane))
	return err
}

// sheerWorkspacePicker chooses a stack or unstacked branch, or accepts a new
// branch name, and opens or creates its worktree workspace.
func (c *client) sheerWorkspacePicker(fzf string) error {
	fmt.Fprintln(os.Stderr, "Loading sheer stacks and branches...")
	catalog, err := c.loadSheerCatalog(os.Stderr)
	if err != nil {
		return err
	}
	branch, err := chooseSheerBranch(fzf, catalog.visible())
	if err != nil {
		return err
	}
	if branch == "" {
		return nil
	}
	return c.openOrCreateSheerBranch(branch, catalog)
}

// sheerWorkspaceBranch opens or creates the sheer worktree for branch without
// prompting, so scripts and agents can drive the same workflow as alt+s.
func (c *client) sheerWorkspaceBranch(branch string) error {
	branch = normalizeSheerBranchName(branch)
	if branch == "" {
		return errors.New("branch name cannot be empty")
	}

	catalog, err := c.loadSheerCatalog(os.Stderr)
	if err != nil {
		return err
	}
	return c.openOrCreateSheerBranch(branch, catalog)
}

// sheerWorkspaceList prints the choices the picker offers, as aligned text or
// as JSON, so agents can pick a --branch without opening fzf.
func (c *client) sheerWorkspaceList(output io.Writer, asJSON bool) error {
	catalog, err := c.loadSheerCatalog(os.Stderr)
	if err != nil {
		return err
	}
	choices := catalog.visible()
	if asJSON {
		encoder := json.NewEncoder(output)
		encoder.SetIndent("", "  ")
		return encoder.Encode(choices)
	}
	for _, choice := range choices {
		if _, err := fmt.Fprintln(output, choice.line(false)); err != nil {
			return err
		}
	}
	return nil
}

// openOrCreateSheerBranch resolves branch to its stack or to an unstacked
// branch, then focuses a worktree already on it or creates one. Any layer of
// a stack opens the worktree that stack is already checked out in.
func (c *client) openOrCreateSheerBranch(branch string, catalog sheerCatalog) error {
	choice := catalog.find(branch)
	if worktree, ok := catalog.worktreeFor(branch, choice); ok {
		if worktree.Branch != branch {
			fmt.Fprintf(os.Stdout, "Stack is already checked out at %s on %s; opening it...\n", worktree.Path, worktree.Branch)
		}
		workspaceID, err := c.ensureSheerMainWorkspace()
		if err != nil {
			return err
		}
		return c.openSheerWorktree(workspaceID, worktree)
	}

	return c.createSheerWorkspace(sheerWorktreeRequest{
		Branch: branch,
		Local:  catalog.refs.local[branch],
		Remote: catalog.refs.remote[branch],
	}, os.Stdout)
}

// sheerWorktrees lists usable linked worktrees for the canonical sheer repo.
// The primary checkout is excluded because alt+s is specifically for branch
// workspaces beneath that checkout's Herdr workspace group. Worktrees are
// ordered by how good a workspace they make, so lookups that take the first
// match for a stack prefer an open workspace, then a Herdr-managed checkout,
// over ad hoc checkouts such as agent scratch worktrees.
func (c *client) sheerWorktrees() ([]existingWorktreeInfo, error) {
	var result struct {
		Type      string                 `json:"type"`
		Worktrees []existingWorktreeInfo `json:"worktrees"`
	}
	if err := c.call("worktree.list", map[string]any{"cwd": sheerRepo}, &result); err != nil {
		return nil, err
	}

	worktrees := make([]existingWorktreeInfo, 0, len(result.Worktrees))
	for _, worktree := range result.Worktrees {
		if !worktree.IsLinkedWorktree || worktree.IsPrunable || worktree.Branch == "" {
			continue
		}
		worktrees = append(worktrees, worktree)
	}
	managedRoot := ""
	if home, err := homeDir(); err == nil {
		managedRoot = filepath.Join(home, herdrWorktreeDirectory) + string(filepath.Separator)
	}
	rank := func(worktree existingWorktreeInfo) int {
		switch {
		case worktree.OpenWorkspaceID != "":
			return 0
		case managedRoot != "" && strings.HasPrefix(worktree.Path, managedRoot):
			return 1
		default:
			return 2
		}
	}
	sort.Slice(worktrees, func(i, j int) bool {
		if rank(worktrees[i]) != rank(worktrees[j]) {
			return rank(worktrees[i]) < rank(worktrees[j])
		}
		return worktrees[i].Branch < worktrees[j].Branch
	})
	return worktrees, nil
}

// chooseSheerBranch lists stacks then unstacked branches in fzf, each tagged
// with its kind, and seeds the query with drew/. Every line starts with a
// hidden branch name, so a selection resolves exactly like --branch. Enter
// accepts the selected match, or the typed query when there are no matches;
// alt-enter always takes the typed query so new names can be created even
// when they fuzzily match existing ones. Escape cancels.
func chooseSheerBranch(fzf string, choices []sheerChoice) (string, error) {
	lines := make([]string, 0, len(choices))
	for _, choice := range choices {
		lines = append(lines, choice.Branch+"\t"+choice.line(true))
	}

	cmd := exec.Command(
		fzf,
		"--ansi",
		"--delimiter=\t",
		"--with-nth=2..",
		"--tiebreak=index",
		"--prompt=sheer> ",
		"--header=enter: open stack/branch · alt-enter: create typed branch · ^stack / ^branch: filter kind",
		"--query="+sheerBranchPrefix,
		"--print-query",
		"--bind=enter:accept-or-print-query",
		"--bind=alt-enter:print-query",
	)
	cmd.Stdin = strings.NewReader(strings.Join(lines, "\n") + "\n")
	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	if err := cmd.Run(); err != nil {
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			return "", nil
		}
		return "", fmt.Errorf("run fzf: %w", err)
	}

	output := strings.Split(strings.TrimRight(stdout.String(), "\r\n"), "\n")
	// --print-query writes the query first. A selected match, or the query
	// emitted by accept-or-print-query when there is no match, comes last.
	// Selected lines carry their branch before the first tab.
	branch, _, _ := strings.Cut(output[len(output)-1], "\t")
	return normalizeSheerBranchName(branch), nil
}

// normalizeSheerBranchName trims surrounding whitespace and treats a bare
// prefix as an empty entry so confirming without edits cancels the picker.
func normalizeSheerBranchName(name string) string {
	name = strings.TrimSpace(name)
	if name == sheerBranchPrefix {
		return ""
	}
	return name
}

// ensureSheerMainWorkspace returns the canonical checkout's primary Herdr
// workspace, creating it in the background on main when it is not already open.
func (c *client) ensureSheerMainWorkspace() (string, error) {
	workspaces, err := c.workspaces()
	if err != nil {
		return "", err
	}
	wanted := filepath.Clean(sheerRepo)
	for _, workspace := range workspaces {
		if workspace.Worktree == nil || workspace.Worktree.IsLinkedWorktree {
			continue
		}
		if filepath.Clean(workspace.Worktree.CheckoutPath) == wanted {
			return workspace.WorkspaceID, nil
		}
	}

	if err := runGit(sheerRepo, "switch", "main"); err != nil {
		return "", fmt.Errorf("set canonical sheer checkout to main: %w", err)
	}
	workspace, err := c.createWorkspaceWithFocus(sheerRepo, filepath.Base(sheerRepo), false)
	if err != nil {
		return "", fmt.Errorf("open canonical sheer workspace: %w", err)
	}
	if workspace.WorkspaceID == "" {
		return "", errors.New("canonical sheer workspace did not have an id")
	}
	return workspace.WorkspaceID, nil
}

// openSheerWorktree opens or focuses an existing checkout beneath the
// canonical sheer workspace group. Its picker entry keeps drew/, while the
// resulting workspace label omits it.
func (c *client) openSheerWorktree(workspaceID string, worktree existingWorktreeInfo) error {
	return c.call("worktree.open", map[string]any{
		"focus":        true,
		"label":        sheerBranchLabel(worktree.Branch),
		"path":         worktree.Path,
		"workspace_id": workspaceID,
	}, nil)
}

// sheerWorktreeRequest describes the branch a new worktree is created for and
// where it already exists, which decides the ref it is based on.
type sheerWorktreeRequest struct {
	Branch string
	Local  bool
	Remote bool
}

// createSheerWorkspace updates origin/main and creates a background worktree
// workspace. Existing local branches are checked out as they are, origin
// branches are fetched and reused, and only new branches start from
// origin/main.
func (c *client) createSheerWorkspace(request sheerWorktreeRequest, output io.Writer) error {
	if sheerRepo == "" {
		return errors.New("sheer repository path is not configured")
	}
	branch := request.Branch
	if err := runGit(sheerRepo, "check-ref-format", "--branch", branch); err != nil {
		return fmt.Errorf("invalid branch name %q: %w", branch, err)
	}

	fmt.Fprintf(output, "Fetching %s in %s...\n", sheerBaseBranch, sheerRepo)
	if err := runGit(sheerRepo, "fetch", "origin", "main"); err != nil {
		return fmt.Errorf("update %s: %w", sheerBaseBranch, err)
	}

	base := sheerBaseBranch
	switch {
	case request.Remote:
		fmt.Fprintf(output, "Branch %s already exists on origin; using it...\n", branch)
		if err := runGit(sheerRepo, "fetch", "origin", branch); err != nil {
			return fmt.Errorf("fetch %s: %w", branch, err)
		}
		base = "origin/" + branch
	case request.Local:
		// Herdr checks out an existing local branch and ignores base, but
		// naming the branch itself keeps its upstream from being cleared.
		base = branch
	}

	workspaceID, err := c.ensureSheerMainWorkspace()
	if err != nil {
		return err
	}
	fmt.Fprintf(output, "Creating worktree for %s...\n", branch)
	return c.createSheerWorktree(workspaceID, request, base)
}

// clearBranchUpstream drops the upstream Git configures when a branch starts
// from a remote-tracking ref. Herdr leaves branches from its own worktree
// creation untracked, so without this pull, push, and status would all treat
// main as the new branch's upstream.
func clearBranchUpstream(repo string, branch string) error {
	if !branchHasUpstream(repo, branch) {
		return nil
	}
	return runGit(repo, "branch", "--unset-upstream", branch)
}

// branchHasUpstream reports whether the branch has tracking configured, since
// git branch --unset-upstream fails when there is nothing to unset.
func branchHasUpstream(repo string, branch string) bool {
	command := exec.Command("git", "-C", repo, "config", "--get", "branch."+branch+".merge")
	return command.Run() == nil
}

// runGit runs a Git operation against the canonical sheer checkout while
// keeping command output visible in the creator overlay.
func runGit(repo string, args ...string) error {
	commandArgs := append([]string{"-C", repo}, args...)
	command := exec.Command("git", commandArgs...)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("git %s: %w", strings.Join(commandArgs, " "), err)
	}
	return nil
}

// createSheerWorktree delegates path selection and workspace registration to
// Herdr, then sets up the stack and installs dependencies in the new
// workspace's initial pane. base is the ref the branch grows from; when it is
// origin/main the branch is new and Herdr's inherited tracking is cleared.
func (c *client) createSheerWorktree(workspaceID string, request sheerWorktreeRequest, base string) error {
	branch := request.Branch
	var result struct {
		Type     string              `json:"type"`
		Worktree createdWorktreeInfo `json:"worktree"`
	}
	if err := c.call("worktree.create", map[string]any{
		"base":         base,
		"branch":       branch,
		"focus":        false,
		"label":        sheerBranchLabel(branch),
		"workspace_id": workspaceID,
	}, &result); err != nil {
		return err
	}
	if base == sheerBaseBranch {
		if err := clearBranchUpstream(sheerRepo, branch); err != nil {
			return fmt.Errorf("unset upstream for %s: %w", branch, err)
		}
	}
	if result.Worktree.OpenWorkspaceID == "" {
		return fmt.Errorf("created worktree %q did not have an open workspace", branch)
	}

	pane, err := c.waitForWorkspacePane(result.Worktree.OpenWorkspaceID)
	if err != nil {
		return err
	}
	return c.runPane(pane.PaneID, sheerSetupCommand(branch))
}

// sheerBranchLabel hides a leading drew/ prefix in the workspace label.
func sheerBranchLabel(branch string) string {
	return strings.TrimPrefix(branch, sheerBranchPrefix)
}

// sheerSetupCommand checks out the branch's existing stack, importing it from
// GitHub when it is only tracked there. Only when gh stack finds no local or
// remote stack (exit code 2) is the branch adopted as the first layer of a
// new one, so a stale or failed stack listing can never duplicate a stack.
// Naming the branch keeps gh stack from opening its interactive prompts.
// Workspace panes run nushell, so complete captures gh stack's exit code
// instead of shell redirections.
func sheerSetupCommand(branch string) string {
	quoted := strconv.Quote(branch)
	return "let checkout = (gh stack checkout " + quoted + " | complete); " +
		"if $checkout.exit_code == 2 { gh stack init " + quoted + " } " +
		"else { print -n $checkout.stdout; print -n -e $checkout.stderr }; pnpm install"
}

// waitForWorkspacePane waits for Herdr to publish the initial pane created with
// the worktree workspace.
func (c *client) waitForWorkspacePane(workspaceID string) (paneInfo, error) {
	deadline := time.Now().Add(workspacePaneWait)
	for {
		panes, err := c.panes(workspaceID)
		if err != nil {
			return paneInfo{}, err
		}
		if len(panes) > 0 {
			return panes[0], nil
		}
		if time.Now().After(deadline) {
			return paneInfo{}, fmt.Errorf("created workspace %s did not have a pane", workspaceID)
		}
		time.Sleep(workspacePanePoll)
	}
}

// runPane submits a command and Enter to an existing pane.
func (c *client) runPane(paneID string, command string) error {
	if paneID == "" {
		return errors.New("pane id cannot be empty")
	}
	return c.call("pane.send_input", map[string]any{
		"keys":    []string{"Enter"},
		"pane_id": paneID,
		"text":    command,
	}, nil)
}
