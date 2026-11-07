package herdr

import (
	"cmp"
	"os"
)

// Pane is the subset of Herdr pane metadata herdrctl uses.
type Pane struct {
	CWD           string `json:"cwd"`
	Focused       bool   `json:"focused"`
	ForegroundCWD string `json:"foreground_cwd"`
	Label         string `json:"label"`
	PaneID        string `json:"pane_id"`
	TabID         string `json:"tab_id"`
	Title         string `json:"title"`
	WorkspaceID   string `json:"workspace_id"`
}

// ActiveCWD chooses the best cwd to start tools from: the foreground
// process's, then the pane's, then the one Herdr passed to plugin panes.
func (pane Pane) ActiveCWD() string {
	return cmp.Or(pane.ForegroundCWD, pane.CWD, os.Getenv("HERDR_ACTIVE_PANE_CWD"))
}

// Tab is the subset of Herdr tab metadata herdrctl uses.
type Tab struct {
	Focused     bool   `json:"focused"`
	Label       string `json:"label"`
	Number      int    `json:"number"`
	PaneCount   int    `json:"pane_count"`
	TabID       string `json:"tab_id"`
	WorkspaceID string `json:"workspace_id"`
}

// FocusID returns the identifier used by tab.focus.
func (tab Tab) FocusID() string { return tab.TabID }

// IsFocused reports whether the tab is Herdr's current tab.
func (tab Tab) IsFocused() bool { return tab.Focused }

// Position returns the user-visible tab number.
func (tab Tab) Position() int { return tab.Number }

// WorkspaceWorktree identifies workspaces Herdr displays in the same
// repository group and records the checkout each workspace represents.
type WorkspaceWorktree struct {
	CheckoutPath     string `json:"checkout_path"`
	IsLinkedWorktree bool   `json:"is_linked_worktree"`
	RepoKey          string `json:"repo_key"`
	RepoName         string `json:"repo_name"`
	RepoRoot         string `json:"repo_root"`
}

// Workspace is the subset of Herdr workspace metadata herdrctl uses.
type Workspace struct {
	ActiveTabID string             `json:"active_tab_id"`
	Focused     bool               `json:"focused"`
	Label       string             `json:"label"`
	Number      int                `json:"number"`
	WorkspaceID string             `json:"workspace_id"`
	Worktree    *WorkspaceWorktree `json:"worktree"`
}

// FocusID returns the identifier used by workspace.focus.
func (workspace Workspace) FocusID() string { return workspace.WorkspaceID }

// IsFocused reports whether the workspace is Herdr's current workspace.
func (workspace Workspace) IsFocused() bool { return workspace.Focused }

// Position returns the user-visible workspace number.
func (workspace Workspace) Position() int { return workspace.Number }

// Focusable is an ordered Herdr object that can be focused.
type Focusable interface {
	FocusID() string
	IsFocused() bool
	Position() int
}

// Worktree is the subset of worktree.list and worktree.create entries
// herdrctl uses. OpenWorkspaceID is empty when no workspace shows it.
type Worktree struct {
	Branch           string `json:"branch"`
	IsLinkedWorktree bool   `json:"is_linked_worktree"`
	IsPrunable       bool   `json:"is_prunable"`
	OpenWorkspaceID  string `json:"open_workspace_id"`
	Path             string `json:"path"`
}

// PluginPane describes a plugin pane returned by plugin.pane.open.
type PluginPane struct {
	Entrypoint string `json:"entrypoint"`
	Pane       Pane   `json:"pane"`
	PluginID   string `json:"plugin_id"`
}

// Focus holds the IDs of the pane, tab, and workspace a command acts on.
type Focus struct {
	PaneID      string
	TabID       string
	WorkspaceID string
}
