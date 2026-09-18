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

	"golang.org/x/term"
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

// newWorkspace prompts for a branch name, updates origin/main, and creates a
// background Herdr worktree workspace. The name is used verbatim as the branch
// while the workspace label omits a leading drew/ prefix.
func (c *client) newWorkspace() error {
	return c.newWorkspaceFrom(os.Stdin, os.Stdout)
}

func (c *client) newWorkspaceFrom(input io.Reader, output io.Writer) error {
	branch, err := promptSheerWorktreeName(input, output)
	if err != nil {
		return err
	}
	if branch == "" {
		return nil
	}
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

	fmt.Fprintf(output, "Creating worktree for %s...\n", branch)
	return c.createSheerWorktree(branch, base)
}

// promptSheerWorktreeName returns the branch name to create. On a terminal the
// input starts prefilled with drew/, backspaced like any other character, so
// the entry can also begin without it. Non-terminal input (tests, pipes) is
// read line by line and used verbatim. An empty name cancels the prompt.
func promptSheerWorktreeName(input io.Reader, output io.Writer) (string, error) {
	fmt.Fprint(output, "\x1b[36menter worktree name:\x1b[0m ")

	file, isFile := input.(*os.File)
	if !isFile || !term.IsTerminal(int(file.Fd())) {
		scanner := bufio.NewScanner(input)
		if !scanner.Scan() {
			return "", scanner.Err()
		}
		return normalizeSheerBranchName(scanner.Text()), nil
	}

	name, err := promptPrefilledLine(file, output)
	if err != nil {
		return "", err
	}
	return normalizeSheerBranchName(name), nil
}

// normalizeSheerBranchName trims surrounding whitespace and treats a bare
// prefix as an empty entry so confirming without edits cancels the prompt.
func normalizeSheerBranchName(name string) string {
	name = strings.TrimSpace(name)
	if name == sheerBranchPrefix {
		return ""
	}
	return name
}

// promptPrefilledLine edits a line in raw terminal mode, seeded with drew/, so
// every keystroke including backspaces applies to the prefix. Raw mode also
// disables the terminal's echo, so the buffer is redrawn after each change.
func promptPrefilledLine(file *os.File, output io.Writer) (string, error) {
	fd := int(file.Fd())
	oldState, err := term.MakeRaw(fd)
	if err != nil {
		return "", fmt.Errorf("enable raw mode for branch prompt: %w", err)
	}
	defer term.Restore(fd, oldState)

	name := []rune(sheerBranchPrefix)
	render := func() {
		fmt.Fprintf(output, "\r\x1b[2K\x1b[36menter worktree name:\x1b[0m %s", string(name))
	}
	render()

	reader := bufio.NewReader(file)
	for {
		char, _, err := reader.ReadRune()
		if err != nil {
			return "", err
		}
		switch char {
		case '\r', '\n':
			fmt.Fprint(output, "\r\n")
			return string(name), nil
		case 0x08, 0x7f: // backspace and delete
			if len(name) > 0 {
				name = name[:len(name)-1]
				render()
			}
		case 0x03, 0x04: // ctrl-c and ctrl-d cancel
			fmt.Fprint(output, "\r\n")
			return "", nil
		case 0x1b: // escape sequence; ignore it whole
			if err := discardEscapeSequence(reader); err != nil {
				return "", err
			}
		default:
			if char < 0x20 {
				continue
			}
			name = append(name, char)
			render()
		}
	}
}

// discardEscapeSequence consumes one terminal escape sequence after a lone
// ESC so arrow keys and similar input do not leak into the branch name.
func discardEscapeSequence(reader *bufio.Reader) error {
	next, _, err := reader.ReadRune()
	if err != nil {
		return err
	}
	if next != '[' && next != 'O' {
		return nil
	}
	for {
		char, _, err := reader.ReadRune()
		if err != nil {
			return err
		}
		if char >= 0x40 && char <= 0x7e {
			return nil
		}
	}
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
func (c *client) createSheerWorktree(branch string, base string) error {
	var result struct {
		Type     string              `json:"type"`
		Worktree createdWorktreeInfo `json:"worktree"`
	}
	if err := c.call("worktree.create", map[string]any{
		"base":   base,
		"branch": branch,
		"cwd":    sheerRepo,
		"focus":  false,
		"label":  sheerBranchLabel(branch),
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
