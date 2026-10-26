package main

import (
	"fmt"

	"herdr-keybinds/internal/herdr"
)

// pluginID is this helper's Herdr plugin, which owns its overlay panes.
const pluginID = "drew.herdr-keybinds"

// client is a Herdr client with herdrctl's keybinding actions as methods.
type client struct {
	*herdr.Client
}

// runWithClient creates a Herdr client and runs one command action with it.
func runWithClient(action func(*client) error) error {
	herdrClient, err := herdr.NewClient()
	if err != nil {
		return fmt.Errorf("create client: %w", err)
	}
	return action(&client{herdrClient})
}

// openOverlay opens one of this plugin's panes as an overlay.
func (c *client) openOverlay(entrypoint string, cwd string) (herdr.PluginPane, error) {
	return c.OpenPluginOverlay(pluginID, entrypoint, cwd)
}

// openPickerOverlay opens a picker entrypoint as an overlay that starts in
// the active pane's directory.
func (c *client) openPickerOverlay(entrypoint string) error {
	pane, err := c.CurrentPane()
	if err != nil {
		return err
	}
	_, err = c.openOverlay(entrypoint, pane.ActiveCWD())
	return err
}
