package herdr

import (
	"path/filepath"

	"herdr-keybinds/internal/xdg"
)

// managedWorktreeDirectory is Herdr's default worktrees.directory, relative
// to $HOME, where it creates managed checkouts.
const managedWorktreeDirectory = ".herdr/worktrees"

// Worktrees lists the Git worktrees of the repository containing cwd.
func (c *Client) Worktrees(cwd string) ([]Worktree, error) {
	var result struct {
		Worktrees []Worktree `json:"worktrees"`
	}
	if err := c.Call("worktree.list", map[string]any{"cwd": cwd}, &result); err != nil {
		return nil, err
	}
	return result.Worktrees, nil
}

// OpenWorktree opens or focuses an existing checkout at path as a workspace
// in workspaceID's repository group.
func (c *Client) OpenWorktree(workspaceID string, path string, label string) error {
	return c.Call("worktree.open", map[string]any{
		"focus":        true,
		"label":        label,
		"path":         path,
		"workspace_id": workspaceID,
	}, nil)
}

// NewWorktree describes a worktree for CreateWorktree. Herdr checks out
// Branch when it already exists locally and otherwise creates it from Base.
type NewWorktree struct {
	WorkspaceID string
	Branch      string
	Base        string
	Label       string
}

// CreateWorktree creates a checkout at Herdr's default path and opens it as
// a background workspace in the source workspace's repository group.
func (c *Client) CreateWorktree(worktree NewWorktree) (Worktree, error) {
	var result struct {
		Worktree Worktree `json:"worktree"`
	}
	err := c.Call("worktree.create", map[string]any{
		"base":         worktree.Base,
		"branch":       worktree.Branch,
		"focus":        false,
		"label":        worktree.Label,
		"workspace_id": worktree.WorkspaceID,
	}, &result)
	return result.Worktree, err
}

// ManagedWorktreeRoot returns the directory Herdr creates worktrees under,
// with a trailing separator so it can be used as a path prefix.
func ManagedWorktreeRoot() (string, error) {
	home, err := xdg.Home()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, managedWorktreeDirectory) + string(filepath.Separator), nil
}
