package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

var logger = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{}))

func main() {
	slog.SetDefault(logger)

	if len(os.Args) < 2 {
		fatal("usage", "message", fmt.Sprintf("usage: %s kitty-left|kitty-right|kitty-close-tab", filepath.Base(os.Args[0])))
	}

	switch os.Args[1] {
	case "kitty-left":
		runKittyDirection("left")
	case "kitty-right":
		runKittyDirection("right")
	case "kitty-close-tab":
		runKittyCloseTab()
	default:
		fatal("unknown subcommand", "subcommand", os.Args[1])
	}
}

func runKittyDirection(direction string) {
	targetIndex, ok, err := nextKittyTabIndex(direction)
	if err != nil {
		fatal("kitty tab lookup failed", "direction", direction, "error", err)
	}
	if !ok {
		if err := dispatchMoveFocus(direction); err != nil {
			fatal("Hyprland fallback failed", "direction", direction, "error", err)
		}
		return
	}

	if err := focusKittyTab(targetIndex); err != nil {
		fatal("kitty focus-tab failed", "direction", direction, "target_index", targetIndex, "error", err)
	}
}

func runKittyCloseTab() {
	command := exec.Command("kitten", "@", "close-tab", "--self")

	output, err := command.CombinedOutput()
	if err != nil {
		fatal("kitty close-tab failed", "error", err, "output", strings.TrimSpace(string(output)))
	}
}

func dispatchMoveFocus(direction string) error {
	switch direction {
	case "left", "right":
	default:
		return fmt.Errorf("unknown Hyprland direction %q", direction)
	}

	_, err := hyprlandCommand(`/dispatch hl.dsp.focus({ direction = "` + direction + `" })`)
	return err
}

func hyprlandCommand(command string) ([]byte, error) {
	conn, err := net.Dial("unix", hyprCommandSocketPath())
	if err != nil {
		return nil, fmt.Errorf("dial Hyprland command socket: %w", err)
	}
	defer conn.Close()

	if _, err := io.WriteString(conn, command); err != nil {
		return nil, fmt.Errorf("write Hyprland command %q: %w", command, err)
	}

	if unixConn, ok := conn.(*net.UnixConn); ok {
		_ = unixConn.CloseWrite()
	}

	response, err := io.ReadAll(conn)
	if err != nil {
		return nil, fmt.Errorf("read Hyprland response for %q: %w", command, err)
	}

	return bytes.TrimSpace(response), nil
}

func nextKittyTabIndex(direction string) (int, bool, error) {
	output, err := exec.Command("kitten", "@", "ls").Output()
	if err != nil {
		return 0, false, fmt.Errorf("run kitten @ ls: %w", err)
	}

	var osWindows []map[string]any
	if err := json.Unmarshal(output, &osWindows); err != nil {
		return 0, false, fmt.Errorf("decode kitten @ ls output: %w", err)
	}

	var focusedWindow map[string]any
	for _, candidate := range osWindows {
		if boolField(candidate, "is_focused") {
			focusedWindow = candidate
			break
		}
	}
	if focusedWindow == nil {
		for _, candidate := range osWindows {
			tabs, ok := candidate["tabs"].([]any)
			if !ok {
				continue
			}
			for _, value := range tabs {
				tab, ok := value.(map[string]any)
				if ok && boolField(tab, "is_focused") {
					focusedWindow = candidate
					break
				}
			}
			if focusedWindow != nil {
				break
			}
		}
	}

	if focusedWindow == nil {
		if len(osWindows) == 1 {
			focusedWindow = osWindows[0]
		} else {
			return 0, false, errors.New("could not identify focused kitty OS window")
		}
	}

	tabValues, ok := focusedWindow["tabs"].([]any)
	if !ok {
		return 0, false, errors.New("kitty ls response missing tabs array")
	}

	activeIndex := -1
	for index, value := range tabValues {
		tab, ok := value.(map[string]any)
		if !ok {
			continue
		}
		if boolField(tab, "is_focused") || boolField(tab, "is_active") {
			activeIndex = index
			break
		}
	}

	if activeIndex == -1 {
		return 0, false, errors.New("could not identify active kitty tab")
	}

	switch direction {
	case "left":
		if activeIndex == 0 {
			return 0, false, nil
		}
		return activeIndex - 1, true, nil
	case "right":
		if activeIndex >= len(tabValues)-1 {
			return 0, false, nil
		}
		return activeIndex + 1, true, nil
	default:
		return 0, false, fmt.Errorf("unsupported direction %q", direction)
	}
}

func focusKittyTab(index int) error {
	command := exec.Command("kitten", "@", "focus-tab", "--match", fmt.Sprintf("index:%d", index))

	output, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("run focus-tab index:%d: %w (%s)", index, err, strings.TrimSpace(string(output)))
	}

	return nil
}

func boolField(value map[string]any, field string) bool {
	flagValue, ok := value[field]
	if !ok {
		return false
	}

	boolean, ok := flagValue.(bool)
	return ok && boolean
}

func hyprRuntimeDir() string {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		fatal("missing runtime dir", "env", "XDG_RUNTIME_DIR")
	}

	signature := os.Getenv("HYPRLAND_INSTANCE_SIGNATURE")
	if signature == "" {
		fatal("missing Hyprland signature", "env", "HYPRLAND_INSTANCE_SIGNATURE")
	}

	return filepath.Join(runtimeDir, "hypr", signature)
}

func hyprCommandSocketPath() string {
	return filepath.Join(hyprRuntimeDir(), ".socket.sock")
}

func fatal(msg string, args ...any) {
	logger.Error(msg, args...)
	os.Exit(1)
}
