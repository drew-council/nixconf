package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"
)

const pluginID = "drew.herdr-keybinds"

// client sends JSON RPC requests to the Herdr Unix socket.
type client struct {
	nextID     int
	socketPath string
}

// apiError is the error object returned by Herdr RPC responses.
type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// apiCallError wraps a Herdr API error as a Go error.
type apiCallError struct {
	Code    string
	Message string
}

// Error returns the Herdr API error code and message.
func (err *apiCallError) Error() string {
	return fmt.Sprintf("%s: %s", err.Code, err.Message)
}

// response is the common envelope returned by Herdr RPC calls.
type response struct {
	ID     string          `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  *apiError       `json:"error"`
}

// pluginPaneInfo describes a plugin pane returned by plugin.pane.open.
type pluginPaneInfo struct {
	Entrypoint string   `json:"entrypoint"`
	Pane       paneInfo `json:"pane"`
	PluginID   string   `json:"plugin_id"`
}

// pluginPaneOpenResult is the typed result for plugin.pane.open.
type pluginPaneOpenResult struct {
	PluginPane pluginPaneInfo `json:"plugin_pane"`
	Type       string         `json:"type"`
}

// newClient resolves the Herdr socket path and returns a ready RPC client.
func newClient() (*client, error) {
	socketPath := os.Getenv("HERDR_SOCKET_PATH")
	if socketPath == "" {
		configDir, err := herdrConfigDir()
		if err != nil {
			return nil, err
		}
		socketPath = filepath.Join(configDir, "herdr.sock")
	}

	return &client{socketPath: socketPath}, nil
}

// encodeRequest returns one newline-delimited JSON RPC request payload.
func (c *client) encodeRequest(method string, params map[string]any) ([]byte, string, error) {
	c.nextID++
	id := fmt.Sprintf("herdr-keybinds-%d", c.nextID)
	if params == nil {
		params = map[string]any{}
	}

	request := map[string]any{
		"id":     id,
		"method": method,
		"params": params,
	}

	payload, err := json.Marshal(request)
	if err != nil {
		return nil, "", fmt.Errorf("encode %s request: %w", method, err)
	}
	payload = append(payload, '\n')
	return payload, id, nil
}

// dial connects to the Herdr socket for one RPC operation.
func (c *client) dial(method string) (net.Conn, error) {
	dialer := net.Dialer{Timeout: 150 * time.Millisecond}
	conn, err := dialer.Dial("unix", c.socketPath)
	if err != nil {
		return nil, fmt.Errorf("dial Herdr socket %s for %s: %w", c.socketPath, method, err)
	}
	return conn, nil
}

// decodeResponse decodes a JSON RPC response envelope and optional result.
func decodeResponse(method string, id string, line []byte, out any) error {
	var envelope response
	if err := json.Unmarshal(line, &envelope); err != nil {
		return fmt.Errorf("decode %s response: %w", method, err)
	}
	if envelope.Error != nil {
		return &apiCallError{
			Code:    envelope.Error.Code,
			Message: envelope.Error.Message,
		}
	}
	if envelope.ID != id {
		return fmt.Errorf("unexpected response id %q for %q", envelope.ID, id)
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(envelope.Result, out); err != nil {
		return fmt.Errorf("decode %s result: %w", method, err)
	}

	return nil
}

// call sends one JSON RPC request to Herdr and decodes its result into out.
func (c *client) call(method string, params map[string]any, out any) error {
	payload, id, err := c.encodeRequest(method, params)
	if err != nil {
		return err
	}

	conn, err := c.dial(method)
	if err != nil {
		return err
	}
	defer conn.Close()

	if _, err := conn.Write(payload); err != nil {
		return fmt.Errorf("write %s request: %w", method, err)
	}

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		return fmt.Errorf("read %s response: %w", method, err)
	}

	return decodeResponse(method, id, line, out)
}

// currentPane returns the active pane, honoring caller pane env overrides.
func (c *client) currentPane() (paneInfo, error) {
	return c.currentPaneFor(firstEnv("HERDR_PANE_ID", "HERDR_ACTIVE_PANE_ID"))
}

// currentPaneFor returns the current pane from Herdr, optionally scoped to paneID.
func (c *client) currentPaneFor(paneID string) (paneInfo, error) {
	params := map[string]any{}
	if paneID != "" {
		params["caller_pane_id"] = paneID
	}

	var result struct {
		Pane paneInfo `json:"pane"`
		Type string   `json:"type"`
	}
	if err := c.call("pane.current", params, &result); err != nil {
		return paneInfo{}, err
	}

	return result.Pane, nil
}

// focusPane focuses paneID through the public pane.focus endpoint.
//
// Herdr 0.9.0 only re-applies tab geometry after socket requests on a fixed
// allow-list (pane.focus, pane.zoom, pane.split, ...). plugin.pane.open and
// plugin.pane.close are not on it, so an overlay keeps the PTY size it was
// split from instead of the zoomed full-tab size (herdrdev/herdr#3799).
// Focusing the pane afterwards forces the server to resize every pane in the
// viewed tab to its real geometry.
func (c *client) focusPane(paneID string) error {
	if paneID == "" {
		return errors.New("pane id cannot be empty")
	}
	return c.call("pane.focus", map[string]any{"pane_id": paneID}, nil)
}

// panes lists panes, optionally scoped to one workspace.
func (c *client) panes(workspaceID string) ([]paneInfo, error) {
	params := map[string]any{}
	if workspaceID != "" {
		params["workspace_id"] = workspaceID
	}

	var result struct {
		Panes []paneInfo `json:"panes"`
		Type  string     `json:"type"`
	}
	if err := c.call("pane.list", params, &result); err != nil {
		return nil, err
	}

	return result.Panes, nil
}

// tabs lists tabs in a workspace sorted by tab number.
func (c *client) tabs(workspaceID string) ([]tabInfo, error) {
	params := map[string]any{}
	if workspaceID != "" {
		params["workspace_id"] = workspaceID
	}

	var result struct {
		Tabs []tabInfo `json:"tabs"`
		Type string    `json:"type"`
	}
	if err := c.call("tab.list", params, &result); err != nil {
		return nil, err
	}

	sortByNumber(result.Tabs)
	return result.Tabs, nil
}

// workspaces lists all workspaces in the order shown in Herdr's sidebar.
func (c *client) workspaces() ([]workspaceInfo, error) {
	var result struct {
		Type       string          `json:"type"`
		Workspaces []workspaceInfo `json:"workspaces"`
	}
	if err := c.call("workspace.list", nil, &result); err != nil {
		return nil, err
	}

	return orderWorkspacesForNavigation(result.Workspaces), nil
}

// createWorkspace creates a focused Herdr workspace and returns its metadata.
func (c *client) createWorkspace(cwd string, label string) (workspaceInfo, error) {
	var result struct {
		Type      string        `json:"type"`
		Workspace workspaceInfo `json:"workspace"`
	}
	if err := c.call("workspace.create", map[string]any{
		"cwd":   cwd,
		"focus": true,
		"label": label,
	}, &result); err != nil {
		return workspaceInfo{}, err
	}
	if result.Workspace.WorkspaceID != "" {
		return result.Workspace, nil
	}

	workspaces, err := c.workspaces()
	if err != nil {
		return workspaceInfo{}, err
	}
	for _, workspace := range workspaces {
		if workspace.Focused && workspace.Label == label {
			return workspace, nil
		}
	}
	for _, workspace := range workspaces {
		if workspace.Label == label {
			return workspace, nil
		}
	}

	return workspaceInfo{}, nil
}

// activePaneCWD chooses the best pane cwd to pass to plugin overlays.
func activePaneCWD(pane paneInfo) string {
	return firstNonEmpty(pane.ForegroundCWD, pane.CWD, firstEnv("HERDR_ACTIVE_PANE_CWD"))
}

func (c *client) workspaceRootCWDForPane(pane paneInfo) (string, error) {
	if cwd := firstEnv("HERDR_WORKSPACE_CWD", "HERDR_ACTIVE_WORKSPACE_CWD"); cwd != "" {
		return filepath.Clean(cwd), nil
	}
	if pane.WorkspaceID != "" {
		cwd, err := workspaceIdentityCWD(pane.WorkspaceID)
		if err != nil {
			return "", err
		}
		if cwd != "" {
			return filepath.Clean(cwd), nil
		}
	}
	return "", nil
}

func workspaceIdentityCWD(workspaceID string) (string, error) {
	sessionPath, err := herdrSessionPath()
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

func herdrSessionPath() (string, error) {
	if socketPath := os.Getenv("HERDR_SOCKET_PATH"); socketPath != "" {
		return filepath.Join(filepath.Dir(socketPath), "session.json"), nil
	}
	configDir, err := herdrConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, "session.json"), nil
}

func herdrConfigDir() (string, error) {
	if configPath := os.Getenv("HERDR_CONFIG_PATH"); configPath != "" {
		return filepath.Dir(configPath), nil
	}
	configHome, err := xdgBaseDir("XDG_CONFIG_HOME", ".config")
	if err != nil {
		return "", err
	}
	return filepath.Join(configHome, "herdr"), nil
}

// openPluginOverlay opens a helper-owned plugin pane in overlay placement.
//
// The returned result is populated whenever the open succeeded, even if the
// follow-up geometry nudge failed, so callers can still track the pane.
func (c *client) openPluginOverlay(entrypoint string, cwd string) (pluginPaneOpenResult, error) {
	params := map[string]any{
		"entrypoint": entrypoint,
		"focus":      true,
		"placement":  "overlay",
		"plugin_id":  pluginID,
	}
	if cwd != "" {
		params["cwd"] = cwd
	}

	var result pluginPaneOpenResult
	if err := c.call("plugin.pane.open", params, &result); err != nil {
		return result, err
	}
	// Work around herdrdev/herdr#3799: plugin.pane.open leaves the overlay at
	// the size of the pane it was split from. pane.focus makes the server
	// re-apply geometry, resizing the zoomed overlay to the full tab.
	if paneID := result.PluginPane.Pane.PaneID; paneID != "" {
		if err := c.focusPane(paneID); err != nil {
			return result, fmt.Errorf("resize %s overlay: %w", entrypoint, err)
		}
	}
	return result, nil
}
