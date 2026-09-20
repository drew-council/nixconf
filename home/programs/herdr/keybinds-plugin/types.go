package main

// paneInfo is the subset of Herdr pane metadata needed by this helper.
type paneInfo struct {
	CWD           string `json:"cwd"`
	Focused       bool   `json:"focused"`
	ForegroundCWD string `json:"foreground_cwd"`
	Label         string `json:"label"`
	PaneID        string `json:"pane_id"`
	TabID         string `json:"tab_id"`
	Title         string `json:"title"`
	WorkspaceID   string `json:"workspace_id"`
}

// tabInfo is the subset of Herdr tab metadata needed by this helper.
type tabInfo struct {
	Focused     bool   `json:"focused"`
	Label       string `json:"label"`
	Number      int    `json:"number"`
	PaneCount   int    `json:"pane_count"`
	TabID       string `json:"tab_id"`
	WorkspaceID string `json:"workspace_id"`
}

// focusID returns the identifier used by tab.focus.
func (tab tabInfo) focusID() string { return tab.TabID }

// isFocused reports whether the tab is Herdr's current tab.
func (tab tabInfo) isFocused() bool { return tab.Focused }

// number returns the user-visible tab ordering number.
func (tab tabInfo) number() int { return tab.Number }

// workspaceWorktreeInfo identifies workspaces Herdr displays in the same
// repository group and records the checkout represented by each workspace.
type workspaceWorktreeInfo struct {
	CheckoutPath     string `json:"checkout_path"`
	IsLinkedWorktree bool   `json:"is_linked_worktree"`
	RepoKey          string `json:"repo_key"`
	RepoName         string `json:"repo_name"`
	RepoRoot         string `json:"repo_root"`
}

// workspaceInfo is the subset of Herdr workspace metadata needed here.
type workspaceInfo struct {
	ActiveTabID string                 `json:"active_tab_id"`
	Focused     bool                   `json:"focused"`
	Label       string                 `json:"label"`
	Number      int                    `json:"number"`
	WorkspaceID string                 `json:"workspace_id"`
	Worktree    *workspaceWorktreeInfo `json:"worktree"`
}

// focusID returns the identifier used by workspace.focus.
func (workspace workspaceInfo) focusID() string { return workspace.WorkspaceID }

// isFocused reports whether the workspace is Herdr's current workspace.
func (workspace workspaceInfo) isFocused() bool { return workspace.Focused }

// number returns the user-visible workspace ordering number.
func (workspace workspaceInfo) number() int { return workspace.Number }

// numberedFocusable is implemented by ordered Herdr objects that can be focused.
type numberedFocusable interface {
	focusID() string
	isFocused() bool
	number() int
}
