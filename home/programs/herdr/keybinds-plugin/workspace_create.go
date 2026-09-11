package main

const workspaceCreatorEntrypoint = "new-workspace-creator"

// openNewWorkspace opens the future workspace creator as an overlay.
func (c *client) openNewWorkspace() error {
	pane, err := c.currentPane()
	if err != nil {
		return err
	}
	_, err = c.openPluginOverlay(workspaceCreatorEntrypoint, activePaneCWD(pane))
	return err
}

// newWorkspace is reserved for the next job's workspace creation workflow.
func (c *client) newWorkspace() error {
	panic("new workspace creation is not implemented")
}
