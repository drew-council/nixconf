package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const workspacePickerEntrypoint = "new-workspace-picker"

// workspaceRoots is a comma-separated list of workspace root directory names
// under $HOME, overridable at build time via -ldflags -X.
var workspaceRoots = "personal,work"

// workspaceChoice is one selectable workspace candidate for the picker.
type workspaceChoice struct {
	Display string
	Path    string
}

// openWorkspacePicker opens the workspace picker plugin pane as an overlay.
func (c *client) openWorkspacePicker() error {
	pane, err := c.currentPane()
	if err != nil {
		return err
	}
	return c.openPluginOverlay(workspacePickerEntrypoint, activePaneCWD(pane), nil)
}

// newWorkspacePicker runs fzf and opens or focuses the selected workspace.
func (c *client) newWorkspacePicker(fzf string) error {
	home, err := homeDir()
	if err != nil {
		return err
	}

	choices, err := workspaceChoicesFor(home, workspaceRootNames(), extraWorkspaceChoices(home))
	if err != nil {
		return err
	}
	if len(choices) == 0 {
		return nil
	}

	selected, err := chooseWorkspace(fzf, choices)
	if err != nil {
		return err
	}
	if selected == nil {
		return nil
	}

	return c.openOrFocusWorkspace(selected.Path, workspaceLabelForPath(selected.Path))
}

// workspaceRootNames splits the build-time workspaceRoots string into names.
func workspaceRootNames() []string {
	return strings.Split(workspaceRoots, ",")
}

// extraWorkspaceChoices returns picker choices outside the standard workspace roots.
func extraWorkspaceChoices(home string) []workspaceChoice {
	choices := make([]workspaceChoice, 0, len(extraWorkspaceDefinitions))
	for _, workspace := range extraWorkspaceDefinitions {
		choices = append(choices, workspaceChoice{
			Display: workspace.RelativePath,
			Path:    filepath.Join(home, workspace.RelativePath),
		})
	}
	return choices
}

// workspaceLabelForPath returns the compact label used for picker-created workspaces.
func workspaceLabelForPath(path string) string {
	label := filepath.Base(path)
	for _, workspace := range extraWorkspaceDefinitions {
		if label == filepath.Base(workspace.RelativePath) {
			return workspace.LabelPrefix + " " + workspace.RelativePath
		}
	}
	return label
}

// openOrFocusWorkspace focuses an existing cwd workspace or creates it.
func (c *client) openOrFocusWorkspace(cwd string, label string) error {
	workspaceID, err := c.workspaceIDForCWD(cwd)
	if err != nil {
		return err
	}
	if workspaceID != "" {
		return c.call("workspace.focus", map[string]any{"workspace_id": workspaceID}, nil)
	}

	_, err = c.createWorkspace(cwd, label)
	return err
}

// workspaceIDForCWD returns the workspace that already contains cwd.
func (c *client) workspaceIDForCWD(cwd string) (string, error) {
	var result struct {
		Panes []paneInfo `json:"panes"`
		Type  string     `json:"type"`
	}
	if err := c.call("pane.list", nil, &result); err != nil {
		return "", err
	}

	wanted := filepath.Clean(cwd)
	for _, pane := range result.Panes {
		if pane.CWD != "" && filepath.Clean(pane.CWD) == wanted {
			return pane.WorkspaceID, nil
		}
	}

	return "", nil
}

// workspaceChoicesFor scans root directories under home for picker choices.
func workspaceChoicesFor(home string, roots []string, extraChoices []workspaceChoice) ([]workspaceChoice, error) {
	choices := make([]workspaceChoice, 0)
	for _, rootName := range roots {
		rootPath := filepath.Join(home, rootName)
		entries, err := os.ReadDir(rootPath)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", rootPath, err)
		}

		for _, entry := range entries {
			if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
				continue
			}

			display := filepath.ToSlash(filepath.Join(rootName, entry.Name()))
			choices = append(choices, workspaceChoice{
				Display: display,
				Path:    filepath.Join(rootPath, entry.Name()),
			})
		}
	}

	for _, choice := range extraChoices {
		info, err := os.Stat(choice.Path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("stat %s: %w", choice.Path, err)
		}
		if !info.IsDir() {
			continue
		}
		choices = append(choices, choice)
	}

	sortWorkspaceChoices(choices)

	return choices, nil
}

// sortWorkspaceChoices orders choices by zoxide recency, then display name.
func sortWorkspaceChoices(choices []workspaceChoice) {
	ranks := zoxideDirectoryRanks()
	sort.Slice(choices, func(i, j int) bool {
		iRank, iRecent := ranks[filepath.Clean(choices[i].Path)]
		jRank, jRecent := ranks[filepath.Clean(choices[j].Path)]
		if iRecent != jRecent {
			return iRecent
		}
		if iRecent && iRank != jRank {
			return iRank < jRank
		}
		return choices[i].Display < choices[j].Display
	})
}

// zoxideDirectoryRanks returns known directories in zoxide priority order.
func zoxideDirectoryRanks() map[string]int {
	cmd := exec.Command("zoxide", "query", "--list")
	output, err := cmd.Output()
	if err != nil {
		return nil
	}

	ranks := make(map[string]int)
	scanner := bufio.NewScanner(bytes.NewReader(output))
	rank := 0
	for scanner.Scan() {
		path := filepath.Clean(strings.TrimSpace(scanner.Text()))
		if path == "." || path == "" {
			continue
		}
		if _, ok := ranks[path]; ok {
			continue
		}
		ranks[path] = rank
		rank++
	}

	return ranks
}

// chooseWorkspace asks fzf to select one workspace choice.
func chooseWorkspace(fzf string, choices []workspaceChoice) (*workspaceChoice, error) {
	byDisplay := make(map[string]*workspaceChoice, len(choices))
	lines := make([]string, 0, len(choices))
	for index := range choices {
		choice := &choices[index]
		byDisplay[choice.Display] = choice
		lines = append(lines, choice.Display)
	}

	cmd := exec.Command(fzf, "--prompt=workspace> ")
	cmd.Stdin = strings.NewReader(strings.Join(lines, "\n") + "\n")
	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	if err := cmd.Run(); err != nil {
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			return nil, nil
		}
		return nil, fmt.Errorf("run fzf: %w", err)
	}

	selected := strings.TrimRight(stdout.String(), "\r\n")
	if selected == "" {
		return nil, nil
	}

	choice, ok := byDisplay[selected]
	if !ok {
		return nil, nil
	}

	return choice, nil
}
