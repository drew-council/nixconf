// Package xdg resolves the home directory and XDG base directories.
package xdg

import (
	"os"
	"path/filepath"
)

// Home returns HOME when set and otherwise falls back to os.UserHomeDir.
func Home() (string, error) {
	if home := os.Getenv("HOME"); home != "" {
		return home, nil
	}
	return os.UserHomeDir()
}

// ConfigHome returns $XDG_CONFIG_HOME, defaulting to ~/.config.
func ConfigHome() (string, error) {
	return baseDir("XDG_CONFIG_HOME", ".config")
}

// StateHome returns $XDG_STATE_HOME, defaulting to ~/.local/state.
func StateHome() (string, error) {
	return baseDir("XDG_STATE_HOME", filepath.Join(".local", "state"))
}

// CacheHome returns $XDG_CACHE_HOME, defaulting to ~/.cache.
func CacheHome() (string, error) {
	return baseDir("XDG_CACHE_HOME", ".cache")
}

// baseDir returns an XDG base directory or a path under home when unset.
func baseDir(envName string, fallbackRel string) (string, error) {
	if value := os.Getenv(envName); value != "" {
		return value, nil
	}
	home, err := Home()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, fallbackRel), nil
}
