package main

import (
	"errors"
	"fmt"
	"sort"
)

// togglePopup closes the active popup, or replaces all popups of the same kind
// with one attached to the active workspace. The popup name is also the Herdr
// plugin pane ID, so adding a new popup requires no Go changes.
func (c *client) togglePopup(name string) error {
	if name == "" {
		return errors.New("popup name cannot be empty")
	}

	pane, err := c.currentPane()
	if err != nil {
		return err
	}

	state, statePath, err := loadPluginState()
	if err != nil {
		return err
	}

	if isPopupPane(pane, name) {
		closeErr := c.closeTrackedPopupPanes(state, name, []string{pane.PaneID})
		saveErr := savePluginState(statePath, state)
		if closeErr != nil {
			return closeErr
		}
		if saveErr != nil {
			return saveErr
		}
		return c.refocusAfterPopupClose()
	}

	paneIDs, err := c.popupPaneIDs(state, name)
	if err != nil {
		return err
	}
	closeErr := c.closeTrackedPopupPanes(state, name, paneIDs)
	saveErr := savePluginState(statePath, state)
	if closeErr != nil {
		return closeErr
	}
	if saveErr != nil {
		return saveErr
	}

	cwd, err := c.workspaceRootCWDForPane(pane)
	if err != nil {
		return fmt.Errorf("resolve workspace cwd for %s overlay: %w", name, err)
	}
	if cwd == "" {
		return fmt.Errorf("could not resolve workspace cwd for %s overlay", name)
	}

	// Track the pane even when the post-open geometry nudge fails, so the next
	// toggle can still close it.
	result, openErr := c.openPluginOverlay(name, cwd)
	openedPane := result.PluginPane.Pane
	if openedPane.PaneID == "" {
		if openErr != nil {
			return openErr
		}
		return savePluginState(statePath, state)
	}
	if state.PopupPanes == nil {
		state.PopupPanes = make(map[string]map[string]string)
	}
	state.PopupPanes[name] = map[string]string{openedPane.PaneID: openedPane.PaneID}
	saveErr = savePluginState(statePath, state)
	if openErr != nil {
		return openErr
	}
	return saveErr
}

// refocusAfterPopupClose re-applies tab geometry once an overlay is gone.
// plugin.pane.close does not trigger a resize either, so panes that were
// hidden behind the overlay while the terminal changed size would otherwise
// stay stale. Best effort: the popup is already closed at this point.
func (c *client) refocusAfterPopupClose() error {
	pane, err := c.currentPaneFor("")
	if err != nil || pane.PaneID == "" {
		return nil
	}
	return c.focusPane(pane.PaneID)
}

func (c *client) popupPaneIDs(state pluginState, name string) ([]string, error) {
	tracked := state.PopupPanes[name]
	ids := make(map[string]struct{}, len(tracked))
	for _, paneID := range tracked {
		if paneID != "" {
			ids[paneID] = struct{}{}
		}
	}

	panes, err := c.panes("")
	if err != nil {
		return nil, err
	}
	for _, pane := range panes {
		if isPopupPane(pane, name) && pane.PaneID != "" {
			ids[pane.PaneID] = struct{}{}
		}
	}

	paneIDs := make([]string, 0, len(ids))
	for paneID := range ids {
		paneIDs = append(paneIDs, paneID)
	}
	sort.Strings(paneIDs)
	return paneIDs, nil
}

func (c *client) closeTrackedPopupPanes(state pluginState, name string, paneIDs []string) error {
	var firstErr error
	for _, paneID := range paneIDs {
		if paneID == "" {
			continue
		}
		if err := c.call("plugin.pane.close", map[string]any{"pane_id": paneID}, nil); err != nil {
			if !isMissingPluginPane(err) && firstErr == nil {
				firstErr = err
			}
		}
		removePopupPaneID(state, name, paneID)
	}
	return firstErr
}

func removePopupPaneID(state pluginState, name, paneID string) {
	for key, value := range state.PopupPanes[name] {
		if key == paneID || value == paneID {
			delete(state.PopupPanes[name], key)
		}
	}
}

func isPopupPane(pane paneInfo, name string) bool {
	return firstNonEmpty(pane.Label, pane.Title) == name
}

// isActivePopupOverlay prevents navigation bindings from escaping any popup.
func (c *client) isActivePopupOverlay(ctx context) (bool, error) {
	if ctx.PaneID == "" {
		return false, nil
	}
	pane, err := c.currentPane()
	if err != nil {
		return false, err
	}
	for name := range loadPopupNames() {
		if pane.PaneID == ctx.PaneID && isPopupPane(pane, name) {
			return true, nil
		}
	}
	return false, nil
}

// loadPopupNames returns tracked popup names. The pane itself is checked by
// name, while this provides a conservative list for navigation behavior.
func loadPopupNames() map[string]struct{} {
	state, _, err := loadPluginState()
	if err != nil {
		return map[string]struct{}{"lazygit": {}}
	}
	names := make(map[string]struct{}, len(state.PopupPanes))
	for name := range state.PopupPanes {
		names[name] = struct{}{}
	}
	return names
}

func isMissingPluginPane(err error) bool {
	var apiErr *apiCallError
	if !errors.As(err, &apiErr) {
		return false
	}
	return apiErr.Code == "plugin_pane_not_found" || apiErr.Code == "pane_not_found" || apiErr.Code == "not_found"
}
