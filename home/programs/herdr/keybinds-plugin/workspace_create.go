package main

import (
	"bytes"
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
	workspacePaneWait              = 2 * time.Second
	workspacePanePoll              = 50 * time.Millisecond
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

// sheerWorkspacePicker chooses an existing Herdr-managed sheer worktree or
// accepts a new branch name and runs the worktree creation workflow.
func (c *client) sheerWorkspacePicker(fzf string) error {
	if sheerRepo == "" {
		return errors.New("sheer repository path is not configured")
	}

	worktrees, err := c.sheerWorktrees()
	if err != nil {
		return err
	}
	branch, err := chooseSheerBranch(fzf, worktrees)
	if err != nil {
		return err
	}
	if branch == "" {
		return nil
	}

	for _, worktree := range worktrees {
		if worktree.Branch == branch {
			workspaceID, err := c.ensureSheerMainWorkspace()
			if err != nil {
				return err
			}
			return c.openSheerWorktree(workspaceID, worktree)
		}
	}

	return c.createSheerWorkspace(branch, os.Stdout)
}

// sheerWorktrees lists usable linked worktrees for the canonical sheer repo.
// The primary checkout is excluded because alt+s is specifically for branch
// workspaces beneath that checkout's Herdr workspace group.
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
	sort.Slice(worktrees, func(i, j int) bool {
		return worktrees[i].Branch < worktrees[j].Branch
	})
	return worktrees, nil
}

// chooseSheerBranch preloads fzf with full branch names and seeds its query
// with drew/. Enter accepts the selected match, or the typed query when there
// are no matches. Escape still cancels without returning a branch.
func chooseSheerBranch(fzf string, worktrees []existingWorktreeInfo) (string, error) {
	branches := make([]string, 0, len(worktrees))
	for _, worktree := range worktrees {
		branches = append(branches, worktree.Branch)
	}

	cmd := exec.Command(
		fzf,
		"--prompt=sheer branch> ",
		"--query="+sheerBranchPrefix,
		"--print-query",
		"--bind=enter:accept-or-print-query",
	)
	cmd.Stdin = strings.NewReader(strings.Join(branches, "\n") + "\n")
	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	if err := cmd.Run(); err != nil {
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			return "", nil
		}
		return "", fmt.Errorf("run fzf: %w", err)
	}

	lines := strings.Split(strings.TrimRight(stdout.String(), "\r\n"), "\n")
	if len(lines) == 0 {
		return "", nil
	}
	// --print-query writes the query first. A selected match, or the query
	// emitted by accept-or-print-query when there is no match, comes last.
	return normalizeSheerBranchName(lines[len(lines)-1]), nil
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

// createSheerWorkspace updates origin/main and creates a background worktree
// workspace. Existing remote branches are reused; otherwise the branch starts
// from origin/main, matching the previous dedicated new-workspace workflow.
func (c *client) createSheerWorkspace(branch string, output io.Writer) error {
	if sheerRepo == "" {
		return errors.New("sheer repository path is not configured")
	}
	if err := runGit(sheerRepo, "check-ref-format", "--branch", branch); err != nil {
		return fmt.Errorf("invalid branch name %q: %w", branch, err)
	}

	fmt.Fprintf(output, "Fetching %s in %s...\n", sheerBaseBranch, sheerRepo)
	if err := runGit(sheerRepo, "fetch", "origin", "main"); err != nil {
		return fmt.Errorf("update %s: %w", sheerBaseBranch, err)
	}

	base := sheerBaseBranch
	if remoteBranchExists(sheerRepo, branch) {
		fmt.Fprintf(output, "Branch %s already exists on origin; using it...\n", branch)
		if err := runGit(sheerRepo, "fetch", "origin", branch); err != nil {
			return fmt.Errorf("fetch %s: %w", branch, err)
		}
		base = "origin/" + branch
	}

	workspaceID, err := c.ensureSheerMainWorkspace()
	if err != nil {
		return err
	}
	fmt.Fprintf(output, "Creating worktree for %s...\n", branch)
	return c.createSheerWorktree(workspaceID, branch, base)
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

// remoteBranchExists reports whether origin already has a head for branch, in
// which case the worktree should reuse it instead of branching from main.
func remoteBranchExists(repo string, branch string) bool {
	command := exec.Command("git", "-C", repo, "ls-remote", "--heads", "origin", branch)
	output, err := command.Output()
	return err == nil && strings.TrimSpace(string(output)) != ""
}

// createSheerWorktree delegates path selection and workspace registration to
// Herdr, then initializes a stack and installs dependencies in the new
// workspace's initial pane. base is the ref the branch grows from; when it is
// origin/main the branch is new and Herdr's inherited tracking is cleared.
func (c *client) createSheerWorktree(workspaceID string, branch string, base string) error {
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

// sheerSetupCommand adopts the branch as the first stack layer only when it is
// not already in one — locally or on GitHub through its PR — without letting
// gh stack open its interactive branch prompt. Workspace panes run nushell, so
// complete captures gh stack's exit code instead of shell redirections.
func sheerSetupCommand(branch string) string {
	return "if ((gh stack view --json | complete).exit_code == 0) { " +
		"print 'Branch already has a stack; skipping init' } else { gh stack init " +
		strconv.Quote(branch) + " }; pnpm install"
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
