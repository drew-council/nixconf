package main

import (
	"fmt"

	"herdr-keybinds/internal/herdr"
)

// Direction identifies a directional navigation target.
type Direction uint8

const (
	directionInvalid Direction = iota
	directionDown
	directionLeft
	directionRight
	directionUp
)

// paneEdges reports which sides of a pane are at the edge of its tab layout.
type paneEdges struct {
	Down  bool `json:"down"`
	Left  bool `json:"left"`
	Right bool `json:"right"`
	Up    bool `json:"up"`
}

// navigate focuses a pane in dir, falling back to tabs or workspaces at edges.
func (c *client) navigate(dir Direction) error {
	focus, err := c.CurrentFocus()
	if err != nil {
		return err
	}
	if active, err := c.isActivePopupOverlay(focus); err != nil {
		return err
	} else if active {
		return nil
	}

	edges, err := c.paneEdges(focus.PaneID)
	if err != nil {
		return err
	}

	if !edgeValue(edges, dir) {
		params := map[string]any{"direction": dir.String()}
		if focus.PaneID != "" {
			params["caller_pane_id"] = focus.PaneID
		}
		return c.Call("pane.focus_direction", params, nil)
	}

	switch dir {
	case directionLeft, directionRight:
		return c.fallbackTab(focus, dir)
	case directionUp, directionDown:
		return c.fallbackWorkspace(focus, dir)
	default:
		return nil
	}
}

// focusTabLabel focuses the first tab in the current workspace with label.
func (c *client) focusTabLabel(label string) error {
	focus, err := c.CurrentFocus()
	if err != nil {
		return err
	}

	tabs, err := c.Tabs(focus.WorkspaceID)
	if err != nil {
		return err
	}

	for _, tab := range tabs {
		if tab.Label == label {
			return c.Call("tab.focus", map[string]any{"tab_id": tab.TabID}, nil)
		}
	}

	return nil
}

// fallbackTab moves left or right by tab number when pane navigation hits an edge.
func (c *client) fallbackTab(focus herdr.Focus, dir Direction) error {
	tabs, err := c.Tabs(focus.WorkspaceID)
	if err != nil {
		return err
	}

	current, ok := currentItem(tabs, focus.TabID)
	if !ok {
		return nil
	}
	target, ok := adjacentByNumber(tabs, current, dir == directionRight)
	if !ok {
		return nil
	}

	return c.Call("tab.focus", map[string]any{"tab_id": target.FocusID()}, nil)
}

// fallbackWorkspace moves up or down in the workspace sidebar order.
func (c *client) fallbackWorkspace(focus herdr.Focus, dir Direction) error {
	workspaces, err := c.Workspaces()
	if err != nil {
		return err
	}

	current, ok := currentItem(workspaces, focus.WorkspaceID)
	if !ok {
		return nil
	}
	target, ok := adjacentInOrder(workspaces, current, dir == directionDown)
	if !ok {
		return nil
	}

	return c.Call("workspace.focus", map[string]any{"workspace_id": target.FocusID()}, nil)
}

// paneEdges asks Herdr which layout edges paneID touches.
func (c *client) paneEdges(paneID string) (paneEdges, error) {
	params := map[string]any{}
	if paneID != "" {
		params["pane_id"] = paneID
	}

	var result struct {
		Edges paneEdges `json:"edges"`
		Type  string    `json:"type"`
	}
	if err := c.Call("pane.edges", params, &result); err != nil {
		return paneEdges{}, err
	}

	return result.Edges, nil
}

// edgeValue reports whether edges contains dir.
func edgeValue(edges paneEdges, dir Direction) bool {
	switch dir {
	case directionLeft:
		return edges.Left
	case directionRight:
		return edges.Right
	case directionUp:
		return edges.Up
	case directionDown:
		return edges.Down
	default:
		return false
	}
}

// parseDirection converts a CLI argument into a Direction.
func parseDirection(value string) (Direction, error) {
	switch value {
	case "left":
		return directionLeft, nil
	case "right":
		return directionRight, nil
	case "up":
		return directionUp, nil
	case "down":
		return directionDown, nil
	default:
		return directionInvalid, fmt.Errorf("invalid direction %q", value)
	}
}

// String returns the Herdr API string for dir.
func (dir Direction) String() string {
	switch dir {
	case directionLeft:
		return "left"
	case directionRight:
		return "right"
	case directionUp:
		return "up"
	case directionDown:
		return "down"
	default:
		return "invalid"
	}
}

// currentItem returns the focused item, falling back to a matching ID.
func currentItem[T herdr.Focusable](items []T, id string) (T, bool) {
	for _, item := range items {
		if item.IsFocused() {
			return item, true
		}
	}
	for _, item := range items {
		if id != "" && item.FocusID() == id {
			return item, true
		}
	}
	var zero T
	return zero, false
}

// adjacentByNumber finds the closest item before or after current.
func adjacentByNumber[T herdr.Focusable](items []T, current T, forward bool) (T, bool) {
	var target T
	found := false
	for _, item := range items {
		if forward {
			if item.Position() > current.Position() && (!found || item.Position() < target.Position()) {
				target = item
				found = true
			}
			continue
		}
		if item.Position() < current.Position() && (!found || item.Position() > target.Position()) {
			target = item
			found = true
		}
	}
	return target, found
}

// adjacentInOrder returns the neighboring item in an already ordered slice.
func adjacentInOrder[T herdr.Focusable](items []T, current T, forward bool) (T, bool) {
	for index, item := range items {
		if item.FocusID() != current.FocusID() {
			continue
		}

		targetIndex := index - 1
		if forward {
			targetIndex = index + 1
		}
		if targetIndex >= 0 && targetIndex < len(items) {
			return items[targetIndex], true
		}
		break
	}

	var zero T
	return zero, false
}
