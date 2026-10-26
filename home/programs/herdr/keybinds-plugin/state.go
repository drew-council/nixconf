package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"herdr-keybinds/internal/xdg"
)

const stateFileName = "state.json"

// pluginState is persisted across invocations to track helper-owned panes.
type pluginState struct {
	PopupPanes map[string]map[string]string `json:"popup_panes"`
}

// loadPluginState reads persisted helper state, creating defaults if absent.
func loadPluginState() (pluginState, string, error) {
	statePath, err := pluginStatePath()
	if err != nil {
		return pluginState{}, "", err
	}

	state := pluginState{PopupPanes: make(map[string]map[string]string)}
	data, err := os.ReadFile(statePath)
	if errors.Is(err, os.ErrNotExist) {
		return state, statePath, nil
	}
	if err != nil {
		return pluginState{}, "", fmt.Errorf("read plugin state: %w", err)
	}
	if len(data) == 0 {
		return state, statePath, nil
	}
	if err := json.Unmarshal(data, &state); err != nil {
		return pluginState{}, "", fmt.Errorf("decode plugin state: %w", err)
	}
	if state.PopupPanes == nil {
		state.PopupPanes = make(map[string]map[string]string)
	}
	// Migrate state written by older versions, without losing existing overlays.
	var legacy struct {
		LazygitPanes map[string]string `json:"lazygit_panes"`
	}
	if err := json.Unmarshal(data, &legacy); err == nil && len(legacy.LazygitPanes) > 0 {
		state.PopupPanes["lazygit"] = legacy.LazygitPanes
	}

	return state, statePath, nil
}

// savePluginState atomically writes helper state to disk.
func savePluginState(statePath string, state pluginState) error {
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("encode plugin state: %w", err)
	}

	tmpPath := statePath + ".tmp"
	if err := os.WriteFile(tmpPath, append(data, '\n'), 0o600); err != nil {
		return fmt.Errorf("write plugin state: %w", err)
	}
	if err := os.Rename(tmpPath, statePath); err != nil {
		return fmt.Errorf("replace plugin state: %w", err)
	}

	return nil
}

// pluginStatePath resolves and creates the path for persisted state.
func pluginStatePath() (string, error) {
	stateDir, err := pluginStateDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(stateDir, stateFileName), nil
}

// pluginStateDir resolves and creates the directory for persisted helper state.
func pluginStateDir() (string, error) {
	stateDir := os.Getenv("HERDR_PLUGIN_STATE_DIR")
	if stateDir == "" {
		stateHome, err := xdg.StateHome()
		if err != nil {
			return "", err
		}
		stateDir = filepath.Join(stateHome, "herdr-keybinds")
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return "", fmt.Errorf("create plugin state dir: %w", err)
	}
	return stateDir, nil
}
