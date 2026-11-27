// Command hypr-monitor-profile selects a Hyprland monitor profile
// and queues it for the Lua applier in monitor_profiles.lua.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"
)

type profile struct {
	Label     string `json:"label"`
	UseTablet bool   `json:"useTablet"`
}

type config struct {
	Profiles           []profile `json:"profiles"`
	TabletHeadlessName string    `json:"tabletHeadlessName"`
}

func main() {
	profilesJSON := flag.String("profiles-json", "", "JSON file describing available monitor profiles")
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, "Usage: hypr-monitor-profile --profiles-json FILE [LABEL]\n\nWithout LABEL, pick a profile in fuzzel.")
	}
	flag.Parse()
	if *profilesJSON == "" || flag.NArg() > 1 {
		flag.Usage()
		os.Exit(2)
	}
	if err := run(*profilesJSON, flag.Arg(0)); err != nil {
		fmt.Fprintln(os.Stderr, "hypr-monitor-profile:", err)
		os.Exit(1)
	}
}

func runtimeDir() string {
	if dir := os.Getenv("XDG_RUNTIME_DIR"); dir != "" {
		return dir
	}
	return "/tmp"
}

func run(profilesJSON, label string) error {
	if f, err := os.OpenFile(filepath.Join(runtimeDir(), "hypr-monitor-profile.log"), os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o644); err == nil {
		defer f.Close()
		log.SetOutput(f)
	}
	log.Printf("launch WAYLAND_DISPLAY=%s", os.Getenv("WAYLAND_DISPLAY"))

	cfg, err := loadConfig(profilesJSON)
	if err != nil {
		return err
	}
	if label == "" {
		if label, err = choose(cfg.Profiles); label == "" || err != nil {
			return err
		}
	}

	i := slices.IndexFunc(cfg.Profiles, func(p profile) bool { return p.Label == label })
	if i < 0 {
		exec.Command("notify-send", "hyprmonitor", "unknown monitor profile: "+label).Run()
		return fmt.Errorf("unknown monitor profile: %s", label)
	}
	log.Printf("selected %s", label)
	setTabletHeadless(cfg.Profiles[i].UseTablet, cfg.TabletHeadlessName)
	return queueRequest(runtimeDir(), label)
}

func loadConfig(path string) (config, error) {
	var cfg config
	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, err
	}
	return cfg, json.Unmarshal(data, &cfg)
}

// choose asks for a profile in fuzzel.
// It returns "" when the menu is dismissed.
func choose(profiles []profile) (string, error) {
	labels := make([]string, len(profiles))
	for i, p := range profiles {
		labels[i] = p.Label
	}
	cmd := exec.Command("fuzzel", "--dmenu", "--prompt", "Monitors> ")
	cmd.Stdin = strings.NewReader(strings.Join(labels, "\n") + "\n")
	out, err := cmd.Output()
	if _, ok := errors.AsType[*exec.ExitError](err); ok {
		log.Printf("fuzzel exited: %v", err)
		return "", nil
	}
	return strings.TrimSpace(string(out)), err
}

// setTabletHeadless creates or removes the headless output for the tablet display.
// Failures are logged, since removing an absent output is expected.
func setTabletHeadless(enabled bool, name string) {
	args := []string{"output", "remove", name}
	if enabled {
		args = []string{"output", "create", "headless", name}
	}
	out, _ := exec.Command("hyprctl", args...).CombinedOutput()
	for line := range strings.Lines(string(out)) {
		log.Printf("hyprctl: %s", strings.TrimSpace(line))
	}
}

// queueRequest writes the request file that monitor_profiles.lua polls:
// a unique request ID, then the profile label.
func queueRequest(dir, label string) error {
	id := strconv.FormatInt(time.Now().UnixNano(), 10)
	log.Printf("queued request %s for %s", id, label)
	return os.WriteFile(filepath.Join(dir, "hyprmonitor-profile-request"), []byte(id+"\n"+label+"\n"), 0o644)
}
