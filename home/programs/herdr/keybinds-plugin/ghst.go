package main

import "fmt"

// ghstLeftPaneRatio leaves one third of the source pane for ghst.
const ghstLeftPaneRatio = 2.0 / 3.0

func (c *client) openGhst() error {
	pane, err := c.currentPane()
	if err != nil {
		return err
	}

	var result struct {
		Pane paneInfo `json:"pane"`
	}
	if err := c.call("pane.split", map[string]any{
		"target_pane_id": pane.PaneID,
		"direction":      "right",
		"ratio":          ghstLeftPaneRatio,
		"cwd":            activePaneCWD(pane),
		"focus":          true,
	}, &result); err != nil {
		return fmt.Errorf("split pane for ghst: %w", err)
	}
	if result.Pane.PaneID == "" {
		return fmt.Errorf("split pane for ghst: missing pane id")
	}
	if err := c.call("pane.send_text", map[string]any{
		"pane_id": result.Pane.PaneID,
		"text":    "ghst",
	}, nil); err != nil {
		return fmt.Errorf("send ghst command: %w", err)
	}
	if err := c.call("pane.send_keys", map[string]any{
		"pane_id": result.Pane.PaneID,
		"keys":    []string{"enter"},
	}, nil); err != nil {
		return fmt.Errorf("start ghst: %w", err)
	}
	return nil
}
