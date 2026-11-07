package herdr

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// CurrentPane returns the active pane, honoring caller pane env overrides.
func (c *Client) CurrentPane() (Pane, error) {
	return c.CurrentPaneFor(firstEnv("HERDR_PANE_ID", "HERDR_ACTIVE_PANE_ID"))
}

// CurrentPaneFor returns the current pane from Herdr, optionally scoped to
// paneID.
func (c *Client) CurrentPaneFor(paneID string) (Pane, error) {
	params := map[string]any{}
	if paneID != "" {
		params["caller_pane_id"] = paneID
	}

	var result struct {
		Pane Pane `json:"pane"`
	}
	if err := c.Call("pane.current", params, &result); err != nil {
		return Pane{}, err
	}

	return result.Pane, nil
}

// CurrentFocus fills the active pane, tab, and workspace IDs from the env
// Herdr sets for plugin commands, asking Herdr for any that are missing.
func (c *Client) CurrentFocus() (Focus, error) {
	focus := Focus{
		PaneID:      firstEnv("HERDR_PANE_ID", "HERDR_ACTIVE_PANE_ID"),
		TabID:       firstEnv("HERDR_TAB_ID", "HERDR_ACTIVE_TAB_ID"),
		WorkspaceID: firstEnv("HERDR_WORKSPACE_ID", "HERDR_ACTIVE_WORKSPACE_ID"),
	}
	if focus.PaneID != "" && focus.TabID != "" && focus.WorkspaceID != "" {
		return focus, nil
	}

	pane, err := c.CurrentPaneFor(focus.PaneID)
	if err != nil {
		return focus, err
	}

	if focus.PaneID == "" {
		focus.PaneID = pane.PaneID
	}
	if focus.TabID == "" {
		focus.TabID = pane.TabID
	}
	if focus.WorkspaceID == "" {
		focus.WorkspaceID = pane.WorkspaceID
	}

	return focus, nil
}

// FocusPane focuses paneID through the public pane.focus endpoint.
//
// Herdr 0.9.0 only re-applies tab geometry after socket requests on a fixed
// allow-list (pane.focus, pane.zoom, pane.split, ...). plugin.pane.open and
// plugin.pane.close are not on it, so an overlay keeps the PTY size it was
// split from instead of the zoomed full-tab size (herdrdev/herdr#3799).
// Focusing the pane afterwards forces the server to resize every pane in the
// viewed tab to its real geometry.
func (c *Client) FocusPane(paneID string) error {
	if paneID == "" {
		return errors.New("pane id cannot be empty")
	}
	return c.Call("pane.focus", map[string]any{"pane_id": paneID}, nil)
}

// Panes lists panes, optionally scoped to one workspace.
func (c *Client) Panes(workspaceID string) ([]Pane, error) {
	params := map[string]any{}
	if workspaceID != "" {
		params["workspace_id"] = workspaceID
	}

	var result struct {
		Panes []Pane `json:"panes"`
	}
	if err := c.Call("pane.list", params, &result); err != nil {
		return nil, err
	}

	return result.Panes, nil
}

// WaitForPane waits up to timeout for Herdr to publish the first pane of a
// newly created workspace.
func (c *Client) WaitForPane(workspaceID string, timeout time.Duration) (Pane, error) {
	const poll = 50 * time.Millisecond
	deadline := time.Now().Add(timeout)
	for {
		panes, err := c.Panes(workspaceID)
		if err != nil {
			return Pane{}, err
		}
		if len(panes) > 0 {
			return panes[0], nil
		}
		if time.Now().After(deadline) {
			return Pane{}, fmt.Errorf("workspace %s did not have a pane", workspaceID)
		}
		time.Sleep(poll)
	}
}

// RunInPane submits command and Enter to an existing pane.
func (c *Client) RunInPane(paneID string, command string) error {
	if paneID == "" {
		return errors.New("pane id cannot be empty")
	}
	return c.Call("pane.send_input", map[string]any{
		"keys":    []string{"Enter"},
		"pane_id": paneID,
		"text":    command,
	}, nil)
}

// Tabs lists tabs in a workspace sorted by tab number.
func (c *Client) Tabs(workspaceID string) ([]Tab, error) {
	params := map[string]any{}
	if workspaceID != "" {
		params["workspace_id"] = workspaceID
	}

	var result struct {
		Tabs []Tab `json:"tabs"`
	}
	if err := c.Call("tab.list", params, &result); err != nil {
		return nil, err
	}

	sortByPosition(result.Tabs)
	return result.Tabs, nil
}

// Workspaces lists all workspaces in the order shown in Herdr's sidebar.
func (c *Client) Workspaces() ([]Workspace, error) {
	var result struct {
		Workspaces []Workspace `json:"workspaces"`
	}
	if err := c.Call("workspace.list", nil, &result); err != nil {
		return nil, err
	}

	return sidebarOrder(result.Workspaces), nil
}

// CreateWorkspace creates a Herdr workspace and returns its metadata. Older
// Herdr versions omit the workspace from the response, so it is then looked
// up by checkout path or label.
func (c *Client) CreateWorkspace(cwd string, label string, focus bool) (Workspace, error) {
	var result struct {
		Workspace Workspace `json:"workspace"`
	}
	if err := c.Call("workspace.create", map[string]any{
		"cwd":   cwd,
		"focus": focus,
		"label": label,
	}, &result); err != nil {
		return Workspace{}, err
	}
	if result.Workspace.WorkspaceID != "" {
		return result.Workspace, nil
	}

	workspaces, err := c.Workspaces()
	if err != nil {
		return Workspace{}, err
	}
	wanted := filepath.Clean(cwd)
	for _, workspace := range workspaces {
		if workspace.Worktree != nil && filepath.Clean(workspace.Worktree.CheckoutPath) == wanted {
			return workspace, nil
		}
	}
	for _, workspace := range workspaces {
		if focus && workspace.Focused && workspace.Label == label {
			return workspace, nil
		}
	}
	for _, workspace := range workspaces {
		if workspace.Label == label {
			return workspace, nil
		}
	}

	return Workspace{}, nil
}

// WorkspaceRootCWD returns the root directory of pane's workspace, from the
// env Herdr sets for plugin commands or from its persisted session.
func (c *Client) WorkspaceRootCWD(pane Pane) (string, error) {
	if cwd := firstEnv("HERDR_WORKSPACE_CWD", "HERDR_ACTIVE_WORKSPACE_CWD"); cwd != "" {
		return filepath.Clean(cwd), nil
	}
	if pane.WorkspaceID != "" {
		cwd, err := WorkspaceIdentityCWD(pane.WorkspaceID)
		if err != nil {
			return "", err
		}
		if cwd != "" {
			return filepath.Clean(cwd), nil
		}
	}
	return "", nil
}

// WorkspaceIdentityCWD reads the directory a workspace was created for from
// Herdr's persisted session, which the socket API does not expose.
func WorkspaceIdentityCWD(workspaceID string) (string, error) {
	sessionPath, err := sessionPath()
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(sessionPath)
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("read Herdr session: %w", err)
	}

	var session struct {
		Workspaces []struct {
			ID          string `json:"id"`
			IdentityCWD string `json:"identity_cwd"`
		} `json:"workspaces"`
	}
	if err := json.Unmarshal(data, &session); err != nil {
		return "", fmt.Errorf("decode Herdr session: %w", err)
	}
	for _, workspace := range session.Workspaces {
		if workspace.ID == workspaceID {
			return workspace.IdentityCWD, nil
		}
	}
	return "", nil
}

// OpenPluginOverlay opens one of pluginID's panes in overlay placement.
//
// The returned pane is populated whenever the open succeeded, even if the
// follow-up geometry nudge failed, so callers can still track the pane.
func (c *Client) OpenPluginOverlay(pluginID string, entrypoint string, cwd string) (PluginPane, error) {
	params := map[string]any{
		"entrypoint": entrypoint,
		"focus":      true,
		"placement":  "overlay",
		"plugin_id":  pluginID,
	}
	if cwd != "" {
		params["cwd"] = cwd
	}

	var result struct {
		PluginPane PluginPane `json:"plugin_pane"`
	}
	if err := c.Call("plugin.pane.open", params, &result); err != nil {
		return result.PluginPane, err
	}
	// Work around herdrdev/herdr#3799: plugin.pane.open leaves the overlay at
	// the size of the pane it was split from. pane.focus makes the server
	// re-apply geometry, resizing the zoomed overlay to the full tab.
	if paneID := result.PluginPane.Pane.PaneID; paneID != "" {
		if err := c.FocusPane(paneID); err != nil {
			return result.PluginPane, fmt.Errorf("resize %s overlay: %w", entrypoint, err)
		}
	}
	return result.PluginPane, nil
}

// firstEnv returns the first non-empty environment variable value.
func firstEnv(names ...string) string {
	for _, name := range names {
		if value := os.Getenv(name); value != "" {
			return value
		}
	}
	return ""
}
