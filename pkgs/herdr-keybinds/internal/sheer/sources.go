package sheer

import (
	"bufio"
	"bytes"
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
)

const (
	// stackCatalogFile is gh stack's catalog of local stacks, kept in the
	// repository's common Git directory.
	stackCatalogFile    = "gh-stack"
	remoteRefsPrefix    = "refs/remotes/origin/"
	localRefsPrefix     = "refs/heads/"
	githubStacksPerPage = 100
)

// readLocalStacks reads gh stack's catalog from the repository's common Git
// directory. gh stack has no listing command, so this mirrors the fields its
// own checkout picker reads from the same file.
func readLocalStacks(dir string) ([]catalogEntry, error) {
	output, err := exec.Command("git", "-C", dir, "rev-parse", "--path-format=absolute", "--git-common-dir").Output()
	if err != nil {
		return nil, fmt.Errorf("find git common dir for %s: %w", dir, err)
	}
	path := filepath.Join(strings.TrimSpace(string(output)), stackCatalogFile)
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	return parseLocalStacks(data)
}

// parseLocalStacks decodes gh stack's local catalog file.
func parseLocalStacks(data []byte) ([]catalogEntry, error) {
	var catalog struct {
		Stacks []struct {
			Number   int `json:"number"`
			Branches []struct {
				Branch      string `json:"branch"`
				PullRequest *struct {
					Merged bool `json:"merged"`
				} `json:"pullRequest"`
			} `json:"branches"`
		} `json:"stacks"`
	}
	if err := json.Unmarshal(data, &catalog); err != nil {
		return nil, fmt.Errorf("parse gh stack catalog: %w", err)
	}

	stacks := make([]catalogEntry, 0, len(catalog.Stacks))
	for _, stack := range catalog.Stacks {
		if len(stack.Branches) == 0 {
			continue
		}
		choice := catalogEntry{Kind: entryStack, Number: stack.Number, Local: true}
		for _, branch := range stack.Branches {
			choice.Branches = append(choice.Branches, stackLayer{
				Name:   branch.Branch,
				Merged: branch.PullRequest != nil && branch.PullRequest.Merged,
			})
		}
		stacks = append(stacks, choice)
	}
	return stacks, nil
}

// githubStackPage is one page of the Stacks API, kept with the ETag that
// lets a later request revalidate it.
type githubStackPage struct {
	ETag string          `json:"etag,omitempty"`
	Body json.RawMessage `json:"body"`
}

// fetchGitHubStackPages lists the repository's stacks from GitHub's Stacks
// REST API, the same endpoint gh stack checkout uses to find remote-only
// stacks. Pages from previous are revalidated by ETag, and GitHub answers
// unchanged ones with 304 Not Modified, which does not count against the rate
// limit. Previously seen pages are requested concurrently; pages beyond them
// are followed one at a time while they come back full.
func fetchGitHubStackPages(dir string, previous []githubStackPage) ([]githubStackPage, error) {
	cachedPage := func(index int) *githubStackPage {
		if index < len(previous) {
			return &previous[index]
		}
		return nil
	}

	pages := make([]githubStackPage, max(len(previous), 1))
	errs := make([]error, len(pages))
	var wait sync.WaitGroup
	for index := range pages {
		wait.Go(func() {
			pages[index], errs[index] = fetchGitHubStackPage(dir, index+1, cachedPage(index))
		})
	}
	wait.Wait()
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}

	// Stacks are listed newest first, so new stacks push older ones onto
	// later pages, and closed ones can shorten the list.
	for index := 0; ; index++ {
		if index == len(pages) {
			page, err := fetchGitHubStackPage(dir, index+1, cachedPage(index))
			if err != nil {
				return nil, err
			}
			pages = append(pages, page)
		}
		var stacks []json.RawMessage
		if err := json.Unmarshal(pages[index].Body, &stacks); err != nil {
			return nil, fmt.Errorf("parse GitHub stacks page %d: %w", index+1, err)
		}
		if len(stacks) < githubStacksPerPage {
			return pages[:index+1], nil
		}
	}
}

// fetchGitHubStackPage requests one page of stacks, sending cached's ETag so
// an unchanged page can be answered with 304 and reused.
func fetchGitHubStackPage(dir string, number int, cached *githubStackPage) (githubStackPage, error) {
	args := []string{
		"api", "--include",
		fmt.Sprintf("repos/{owner}/{repo}/stacks?per_page=%d&page=%d", githubStacksPerPage, number),
	}
	if cached != nil && cached.ETag != "" {
		args = append(args, "--header", "If-None-Match: "+cached.ETag)
	}
	command := exec.Command("gh", args...)
	command.Dir = dir
	var stderr bytes.Buffer
	command.Stderr = &stderr
	// gh exits non-zero for 304, so the status line decides the outcome.
	output, runErr := command.Output()
	status, etag, body, parseErr := parseIncludedResponse(output)
	switch {
	case parseErr == nil && status == http.StatusNotModified && cached != nil:
		return *cached, nil
	case parseErr == nil && status == http.StatusOK && runErr == nil:
		return githubStackPage{ETag: etag, Body: body}, nil
	}
	return githubStackPage{}, fmt.Errorf("gh api stacks page %d: %w: %s",
		number, cmp.Or(runErr, parseErr, fmt.Errorf("HTTP %d", status)), strings.TrimSpace(stderr.String()))
}

// parseIncludedResponse splits gh api --include output into its status code,
// ETag header, and body.
func parseIncludedResponse(output []byte) (int, string, []byte, error) {
	head, body, found := bytes.Cut(output, []byte("\r\n\r\n"))
	if !found {
		head, body, found = bytes.Cut(output, []byte("\n\n"))
	}
	if !found {
		return 0, "", nil, errors.New("response has no header terminator")
	}
	lines := strings.Split(string(head), "\n")
	status := strings.Fields(lines[0])
	if len(status) < 2 || !strings.HasPrefix(status[0], "HTTP/") {
		return 0, "", nil, fmt.Errorf("malformed status line %q", lines[0])
	}
	code, err := strconv.Atoi(status[1])
	if err != nil {
		return 0, "", nil, fmt.Errorf("malformed status line %q", lines[0])
	}
	etag := ""
	for _, line := range lines[1:] {
		name, value, ok := strings.Cut(strings.TrimRight(line, "\r"), ":")
		if ok && strings.EqualFold(strings.TrimSpace(name), "etag") {
			etag = strings.TrimSpace(value)
		}
	}
	return code, etag, body, nil
}

// parseRemoteStacks decodes cached Stacks API pages.
func parseRemoteStacks(pages []githubStackPage) ([]catalogEntry, error) {
	var stacks []catalogEntry
	for index, page := range pages {
		var entries []struct {
			Number       int `json:"number"`
			PullRequests []struct {
				MergedAt *string `json:"merged_at"`
				Head     struct {
					Ref string `json:"ref"`
				} `json:"head"`
			} `json:"pull_requests"`
		}
		if err := json.Unmarshal(page.Body, &entries); err != nil {
			return nil, fmt.Errorf("parse GitHub stacks page %d: %w", index+1, err)
		}
		for _, stack := range entries {
			if stack.Number <= 0 || len(stack.PullRequests) == 0 {
				continue
			}
			choice := catalogEntry{Kind: entryStack, Number: stack.Number, Remote: true}
			for _, pr := range stack.PullRequests {
				choice.Branches = append(choice.Branches, stackLayer{
					Name:   pr.Head.Ref,
					Merged: pr.MergedAt != nil && *pr.MergedAt != "",
				})
			}
			stacks = append(stacks, choice)
		}
	}
	return stacks, nil
}

// readBranchRefs reads local branches and origin's remote-tracking branches with
// their commit times. Remote-tracking refs can be stale, so loadCatalog
// replaces the remote set with origin's live heads when it can reach origin.
func readBranchRefs(dir string) (branchRefs, error) {
	output, err := exec.Command(
		"git", "-C", dir, "for-each-ref",
		"--format=%(refname)%09%(committerdate:unix)",
		localRefsPrefix, remoteRefsPrefix,
	).Output()
	if err != nil {
		return branchRefs{}, fmt.Errorf("list branches in %s: %w", dir, err)
	}

	refs := branchRefs{
		local:   make(map[string]bool),
		remote:  make(map[string]bool),
		updated: make(map[string]int64),
	}
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		ref, timestamp, _ := strings.Cut(scanner.Text(), "\t")
		var name string
		if local, ok := strings.CutPrefix(ref, localRefsPrefix); ok {
			name = local
			refs.local[name] = true
		} else if remote, ok := strings.CutPrefix(ref, remoteRefsPrefix); ok {
			name = remote
			refs.remote[name] = true
		} else {
			continue
		}
		updated, _ := strconv.ParseInt(timestamp, 10, 64)
		refs.updated[name] = max(refs.updated[name], updated)
	}
	return refs, nil
}

// fetchOriginHeads lists branch names currently on origin.
func fetchOriginHeads(dir string) (map[string]bool, error) {
	output, err := exec.Command("git", "-C", dir, "ls-remote", "--heads", "origin").Output()
	if err != nil {
		return nil, fmt.Errorf("git ls-remote origin: %w", err)
	}
	heads := make(map[string]bool)
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		_, ref, _ := strings.Cut(scanner.Text(), "\t")
		if name, ok := strings.CutPrefix(ref, localRefsPrefix); ok {
			heads[name] = true
		}
	}
	return heads, nil
}
