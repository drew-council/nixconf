package sheer

import (
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

	"herdr-keybinds/internal/fetchcache"
	"herdr-keybinds/internal/herdr"
)

const (
	// branchPrefix is offered as the start of every branch name and hidden
	// from workspace labels.
	branchPrefix = "drew/"
	// baseBranch is where new branches start.
	baseBranch = "origin/main"
	// workspacePaneWait bounds how long a new workspace has to publish its
	// first pane before setup gives up.
	workspacePaneWait = 2 * time.Second
)

// open opens or creates the sheer worktree for branch without
// prompting, so scripts and agents can drive the same workflow as alt+s.
func (r *repo) open(branch string, mode fetchcache.Mode) error {
	branch = normalizeBranchName(branch)
	if branch == "" {
		return errors.New("branch name cannot be empty")
	}

	catalog, err := r.loadCatalog(os.Stderr, mode)
	if err != nil {
		return err
	}
	return r.openOrCreate(branch, catalog)
}

// openOrCreate resolves branch to its stack or to an unstacked
// branch, then focuses a worktree already on it or creates one. Any layer of
// a stack opens the worktree that stack is already checked out in.
func (r *repo) openOrCreate(branch string, catalog branchCatalog) error {
	choice := catalog.find(branch)
	if worktree, ok := catalog.worktreeFor(branch, choice); ok {
		if worktree.Branch != branch {
			fmt.Fprintf(os.Stdout, "Stack is already checked out at %s on %s; opening it...\n", worktree.Path, worktree.Branch)
		}
		workspaceID, err := r.ensureMainWorkspace()
		if err != nil {
			return err
		}
		return r.openWorktree(workspaceID, worktree)
	}

	return r.createWorkspace(worktreeRequest{
		Branch: branch,
		Local:  catalog.refs.local[branch],
		Remote: catalog.refs.remote[branch],
	}, os.Stdout)
}

// worktrees lists usable linked worktrees of the checkout.
// The primary checkout is excluded because alt+s is specifically for branch
// workspaces beneath that checkout's Herdr workspace group. Worktrees are
// ordered by how good a workspace they make, so lookups that take the first
// match for a stack prefer an open workspace, then a Herdr-managed checkout,
// over ad hoc checkouts such as agent scratch worktrees.
func (r *repo) worktrees() ([]herdr.Worktree, error) {
	listed, err := r.client.Worktrees(r.root)
	if err != nil {
		return nil, err
	}

	worktrees := make([]herdr.Worktree, 0, len(listed))
	for _, worktree := range listed {
		if !worktree.IsLinkedWorktree || worktree.IsPrunable || worktree.Branch == "" {
			continue
		}
		worktrees = append(worktrees, worktree)
	}
	managedRoot, _ := herdr.ManagedWorktreeRoot()
	rank := func(worktree herdr.Worktree) int {
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

// ensureMainWorkspace returns the canonical checkout's primary Herdr
// workspace, creating it in the background on main when it is not already open.
func (r *repo) ensureMainWorkspace() (string, error) {
	workspaces, err := r.client.Workspaces()
	if err != nil {
		return "", err
	}
	wanted := filepath.Clean(r.root)
	for _, workspace := range workspaces {
		if workspace.Worktree == nil || workspace.Worktree.IsLinkedWorktree {
			continue
		}
		if filepath.Clean(workspace.Worktree.CheckoutPath) == wanted {
			return workspace.WorkspaceID, nil
		}
	}

	if err := runGit(r.root, "switch", "main"); err != nil {
		return "", fmt.Errorf("set canonical sheer checkout to main: %w", err)
	}
	workspace, err := r.client.CreateWorkspace(r.root, filepath.Base(r.root), false)
	if err != nil {
		return "", fmt.Errorf("open canonical sheer workspace: %w", err)
	}
	if workspace.WorkspaceID == "" {
		return "", errors.New("canonical sheer workspace did not have an id")
	}
	return workspace.WorkspaceID, nil
}

// openWorktree opens or focuses an existing checkout beneath the
// canonical sheer workspace group. Its picker entry keeps drew/, while the
// resulting workspace label omits it.
func (r *repo) openWorktree(workspaceID string, worktree herdr.Worktree) error {
	return r.client.OpenWorktree(workspaceID, worktree.Path, branchLabel(worktree.Branch))
}

// worktreeRequest describes the branch a new worktree is created for and
// where it already exists, which decides the ref it is based on.
type worktreeRequest struct {
	Branch string
	Local  bool
	Remote bool
}

// createWorkspace updates origin/main and creates a background worktree
// workspace. Existing local branches are checked out as they are, origin
// branches are fetched and reused, and only new branches start from
// origin/main.
func (r *repo) createWorkspace(request worktreeRequest, output io.Writer) error {
	branch := request.Branch
	if err := runGit(r.root, "check-ref-format", "--branch", branch); err != nil {
		return fmt.Errorf("invalid branch name %q: %w", branch, err)
	}

	fmt.Fprintf(output, "Fetching %s in %s...\n", baseBranch, r.root)
	if err := runGit(r.root, "fetch", "origin", "main"); err != nil {
		return fmt.Errorf("update %s: %w", baseBranch, err)
	}

	base := baseBranch
	switch {
	case request.Remote:
		fmt.Fprintf(output, "Branch %s already exists on origin; using it...\n", branch)
		if err := runGit(r.root, "fetch", "origin", branch); err != nil {
			return fmt.Errorf("fetch %s: %w", branch, err)
		}
		base = "origin/" + branch
	case request.Local:
		// Herdr checks out an existing local branch and ignores base, but
		// naming the branch itself keeps its upstream from being cleared.
		base = branch
	}

	workspaceID, err := r.ensureMainWorkspace()
	if err != nil {
		return err
	}
	fmt.Fprintf(output, "Creating worktree for %s...\n", branch)
	return r.createWorktree(workspaceID, request, base)
}

// clearBranchUpstream drops the upstream Git configures when a branch starts
// from a remote-tracking ref. Herdr leaves branches from its own worktree
// creation untracked, so without this pull, push, and status would all treat
// main as the new branch's upstream.
func clearBranchUpstream(dir string, branch string) error {
	if !branchHasUpstream(dir, branch) {
		return nil
	}
	return runGit(dir, "branch", "--unset-upstream", branch)
}

// branchHasUpstream reports whether the branch has tracking configured, since
// git branch --unset-upstream fails when there is nothing to unset.
func branchHasUpstream(dir string, branch string) bool {
	command := exec.Command("git", "-C", dir, "config", "--get", "branch."+branch+".merge")
	return command.Run() == nil
}

// runGit runs a Git operation in dir while keeping command output visible in
// the creator overlay.
func runGit(dir string, args ...string) error {
	commandArgs := append([]string{"-C", dir}, args...)
	command := exec.Command("git", commandArgs...)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("git %s: %w", strings.Join(commandArgs, " "), err)
	}
	return nil
}

// createWorktree delegates path selection and workspace registration to
// Herdr, then sets up the stack and installs dependencies in the new
// workspace's initial pane. base is the ref the branch grows from; when it is
// origin/main the branch is new and Herdr's inherited tracking is cleared.
func (r *repo) createWorktree(workspaceID string, request worktreeRequest, base string) error {
	branch := request.Branch
	created, err := r.client.CreateWorktree(herdr.NewWorktree{
		WorkspaceID: workspaceID,
		Branch:      branch,
		Base:        base,
		Label:       branchLabel(branch),
	})
	if err != nil {
		return err
	}
	if base == baseBranch {
		if err := clearBranchUpstream(r.root, branch); err != nil {
			return fmt.Errorf("unset upstream for %s: %w", branch, err)
		}
	}
	if created.OpenWorkspaceID == "" {
		return fmt.Errorf("created worktree %q did not have an open workspace", branch)
	}

	pane, err := r.client.WaitForPane(created.OpenWorkspaceID, workspacePaneWait)
	if err != nil {
		return err
	}
	return r.client.RunInPane(pane.PaneID, setupCommand(branch))
}

// branchLabel hides a leading drew/ prefix in the workspace label.
func branchLabel(branch string) string {
	return strings.TrimPrefix(branch, branchPrefix)
}

// setupCommand checks out the branch's existing stack, importing it from
// GitHub when it is only tracked there. Only when gh stack finds no local or
// remote stack (exit code 2) is the branch adopted as the first layer of a
// new one, so a stale or failed stack listing can never duplicate a stack.
// Naming the branch keeps gh stack from opening its interactive prompts.
// Workspace panes run nushell, so complete captures gh stack's exit code
// instead of shell redirections.
func setupCommand(branch string) string {
	quoted := strconv.Quote(branch)
	return "let checkout = (gh stack checkout " + quoted + " | complete); " +
		"if $checkout.exit_code == 2 { gh stack init " + quoted + " } " +
		"else { print -n $checkout.stdout; print -n -e $checkout.stderr }; pnpm install"
}
