package sheer

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"herdr-keybinds/internal/fetchcache"
)

// pick chooses a stack or unstacked branch, or accepts a new
// branch name, and opens or creates its worktree workspace. Unless mode asks
// for a refresh, cached GitHub and origin data of any age is shown at once;
// when it is stale, fzf reloads the list from a fresh list run while the
// picker is already open.
func (r *repo) pick(fzf string, mode fetchcache.Mode) error {
	fmt.Fprintln(os.Stderr, "Loading sheer stacks and branches...")
	if mode == fetchcache.Fresh {
		mode = fetchcache.Stale
	}
	catalog, err := r.loadCatalog(os.Stderr, mode)
	if err != nil {
		return err
	}
	reload := ""
	if catalog.stale {
		if reload, err = reloadCommand(); err != nil {
			return err
		}
	}
	branch, err := chooseBranch(fzf, catalog.visible(), reload)
	if err != nil {
		return err
	}
	if branch == "" {
		return nil
	}
	if catalog.stale {
		// Resolve against current data, which the reload has usually cached
		// by now, so a stack created since the stale fetch is still found.
		return r.open(branch, fetchcache.Fresh)
	}
	return r.openOrCreate(branch, catalog)
}

// reloadCommand returns the shell command fzf runs to reload the picker
// with fresh choices. It reruns this binary, which inherits PATH from the
// Nix wrapper through fzf.
func reloadCommand() (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("find herdrctl executable: %w", err)
	}
	return shellQuote(executable) + " sheer-workspace list --fzf", nil
}

// shellQuote quotes value as a single POSIX shell word.
func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", `'\''`) + "'"
}

// listFormat selects how list prints choices.
type listFormat string

const (
	listText listFormat = "text"
	listJSON listFormat = "json"
	// listFzf prints the picker's own input lines, for fzf reloads.
	listFzf listFormat = "fzf"
)

// list prints the choices the picker offers, so agents can pick
// a --branch without opening fzf.
func (r *repo) list(output io.Writer, format listFormat, mode fetchcache.Mode) error {
	catalog, err := r.loadCatalog(os.Stderr, mode)
	if err != nil {
		return err
	}
	choices := catalog.visible()
	switch format {
	case listJSON:
		encoder := json.NewEncoder(output)
		encoder.SetIndent("", "  ")
		return encoder.Encode(choices)
	case listFzf:
		_, err := io.WriteString(output, fzfInput(choices))
		return err
	case listText:
		for _, choice := range choices {
			if _, err := fmt.Fprintln(output, choice.line(false)); err != nil {
				return err
			}
		}
		return nil
	}
	return fmt.Errorf("unknown list format %q", format)
}

// fzfInput renders choices as picker lines. Each starts with the branch
// to open and a tab, which fzf hides from display and matching.
func fzfInput(choices []catalogEntry) string {
	var lines strings.Builder
	for _, choice := range choices {
		lines.WriteString(choice.Branch + "\t" + choice.line(true) + "\n")
	}
	return lines.String()
}

// chooseBranch lists stacks then unstacked branches in fzf, each tagged
// with its kind, and seeds the query with drew/. Every line starts with a
// hidden branch name, so a selection resolves exactly like --branch. Enter
// accepts the selected match, or the typed query when there are no matches;
// alt-enter always takes the typed query so new names can be created even
// when they fuzzily match existing ones. Escape cancels. A non-empty reload
// command replaces the list once it finishes; reload-sync keeps the current
// list usable until then.
func chooseBranch(fzf string, choices []catalogEntry, reload string) (string, error) {
	args := []string{
		"--ansi",
		"--delimiter=\t",
		"--with-nth=2..",
		"--tiebreak=index",
		"--prompt=sheer> ",
		"--header=enter: open stack/branch · alt-enter: create typed branch · ^stack / ^branch: filter kind",
		"--query=" + branchPrefix,
		"--print-query",
		"--bind=enter:accept-or-print-query",
		"--bind=alt-enter:print-query",
	}
	if reload != "" {
		// Pin the shell, since $SHELL may be nushell, which would not run a
		// quoted path as a command.
		args = append(args, "--with-shell=sh -c", "--bind=start:reload-sync:"+reload)
	}
	cmd := exec.Command(fzf, args...)
	cmd.Stdin = strings.NewReader(fzfInput(choices))
	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	if err := cmd.Run(); err != nil {
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			return "", nil
		}
		return "", fmt.Errorf("run fzf: %w", err)
	}

	output := strings.Split(strings.TrimRight(stdout.String(), "\r\n"), "\n")
	// --print-query writes the query first. A selected match, or the query
	// emitted by accept-or-print-query when there is no match, comes last.
	// Selected lines carry their branch before the first tab.
	branch, _, _ := strings.Cut(output[len(output)-1], "\t")
	return normalizeBranchName(branch), nil
}

// normalizeBranchName trims surrounding whitespace and treats a bare
// prefix as an empty entry so confirming without edits cancels the picker.
func normalizeBranchName(name string) string {
	name = strings.TrimSpace(name)
	if name == branchPrefix {
		return ""
	}
	return name
}
