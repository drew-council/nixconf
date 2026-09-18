package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const (
	workspaceCreatorEntrypoint = "new-workspace-creator"
	sheerBranchPrefix          = "drew/"
	sheerBaseBranch            = "origin/main"
	workspacePaneWait          = 2 * time.Second
	workspacePanePoll          = 50 * time.Millisecond
)

// sheerRepo is injected by Nix from vars.workDir so this action always creates
// worktrees from the canonical checkout rather than whichever workspace is open.
var sheerRepo string

// createdWorktreeInfo is the subset returned by worktree.create that is needed
// to start setup in the newly created workspace.
type createdWorktreeInfo struct {
	Branch          string `json:"branch"`
	Label           string `json:"label"`
	OpenWorkspaceID string `json:"open_workspace_id"`
	Path            string `json:"path"`
}

// openNewWorkspace opens sheer worktree creation as an overlay.
func (c *client) openNewWorkspace() error {
	pane, err := c.currentPane()
	if err != nil {
		return err
	}
	_, err = c.openPluginOverlay(workspaceCreatorEntrypoint, activePaneCWD(pane))
	return err
}

// newWorkspace prompts for a branch suffix, updates origin/main, and creates a
// background Herdr worktree workspace. The real branch keeps the required drew/
// prefix while the workspace label omits it.
func (c *client) newWorkspace() error {
	return c.newWorkspaceFrom(os.Stdin, os.Stdout)
}

func (c *client) newWorkspaceFrom(input io.Reader, output io.Writer) error {
	name, err := promptSheerWorktreeName(input, output)
	if err != nil {
		return err
	}
	if name == "" {
		return nil
	}
	if sheerRepo == "" {
		return errors.New("sheer repository path is not configured")
	}

	branch := sheerBranchPrefix + name
	if err := runGit(sheerRepo, "check-ref-format", "--branch", branch); err != nil {
		return fmt.Errorf("invalid branch name %q: %w", branch, err)
	}

	fmt.Fprintf(output, "Fetching %s in %s...\n", sheerBaseBranch, sheerRepo)
	if err := runGit(sheerRepo, "fetch", "origin", "main"); err != nil {
		return fmt.Errorf("update %s: %w", sheerBaseBranch, err)
	}

	fmt.Fprintf(output, "Creating worktree for %s...\n", branch)
	return c.createSheerWorktree(name)
}

// promptSheerWorktreeName accepts either a suffix or an already-prefixed branch
// and returns the suffix used for the workspace's display label.
func promptSheerWorktreeName(input io.Reader, output io.Writer) (string, error) {
	fmt.Fprintf(output, "\x1b[36menter worktree name:\x1b[0m %s", sheerBranchPrefix)

	scanner := bufio.NewScanner(input)
	if !scanner.Scan() {
		return "", scanner.Err()
	}

	name := strings.TrimSpace(scanner.Text())
	name = strings.TrimPrefix(name, sheerBranchPrefix)
	return name, nil
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
// Herdr, then initializes a stack and installs dependencies in the new
// workspace's initial pane.
func (c *client) createSheerWorktree(name string) error {
	branch := sheerBranchPrefix + name
	var result struct {
		Type     string              `json:"type"`
		Worktree createdWorktreeInfo `json:"worktree"`
	}
	if err := c.call("worktree.create", map[string]any{
		"base":   sheerBaseBranch,
		"branch": branch,
		"cwd":    sheerRepo,
		"focus":  false,
		"label":  name,
	}, &result); err != nil {
		return err
	}
	if err := clearBranchUpstream(sheerRepo, branch); err != nil {
		return fmt.Errorf("unset upstream for %s: %w", branch, err)
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

// sheerSetupCommand adopts the already-created branch as the first stack layer
// without letting gh stack open its interactive branch prompt.
func sheerSetupCommand(branch string) string {
	return "gh stack init " + strconv.Quote(branch) + "; pnpm install"
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
