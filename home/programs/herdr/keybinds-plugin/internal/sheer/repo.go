// Package sheer opens Herdr workspaces for the sheer repository's gh stacks
// and branches, each in its own worktree beneath the canonical checkout.
package sheer

import (
	"errors"
	"fmt"
	"io"
	"sync"

	"herdr-keybinds/internal/fetchcache"
	"herdr-keybinds/internal/herdr"
)

// repo opens workspaces for one canonical checkout. Every worktree is
// managed from it, so the result is the same whichever workspace runs it.
type repo struct {
	client *herdr.Client
	root   string
	// cache holds GitHub and origin lookups for this checkout.
	cache fetchcache.Cache
}

// newRepo returns the repo for the checkout at root.
func newRepo(client *herdr.Client, root string) (*repo, error) {
	if root == "" {
		return nil, errors.New("sheer repository path is not configured")
	}
	cache, err := fetchcache.New(root)
	if err != nil {
		return nil, err
	}
	return &repo{client: client, root: root, cache: cache}, nil
}

// loadCatalog gathers worktrees, stacks, and branches for the checkout. GitHub and origin lookups go through the fetch cache
// according to mode and run concurrently because they dominate the latency;
// failures there degrade to cached or local data with a warning.
func (r *repo) loadCatalog(warnings io.Writer, mode fetchcache.Mode) (branchCatalog, error) {
	var (
		wait         sync.WaitGroup
		stackPages   []githubStackPage
		stacksStale  bool
		remoteErr    error
		originHeads  map[string]bool
		originsStale bool
		originErr    error
	)
	wait.Go(func() {
		stackPages, stacksStale, remoteErr = fetchcache.Fetch(r.cache, "github-stacks", mode, warnings,
			func(previous *[]githubStackPage) ([]githubStackPage, error) {
				if previous == nil {
					return fetchGitHubStackPages(r.root, nil)
				}
				return fetchGitHubStackPages(r.root, *previous)
			})
	})
	wait.Go(func() {
		originHeads, originsStale, originErr = fetchcache.Fetch(r.cache, "origin-heads", mode, warnings,
			func(*map[string]bool) (map[string]bool, error) { return fetchOriginHeads(r.root) })
	})

	worktrees, err := r.worktrees()
	if err != nil {
		wait.Wait()
		return branchCatalog{}, err
	}
	localStacks, err := readLocalStacks(r.root)
	if err != nil {
		wait.Wait()
		return branchCatalog{}, err
	}
	refs, err := readBranchRefs(r.root)
	if err != nil {
		wait.Wait()
		return branchCatalog{}, err
	}
	wait.Wait()

	remoteStacks, err := parseRemoteStacks(stackPages)
	if remoteErr == nil && err != nil {
		remoteErr = err
	}
	if remoteErr != nil {
		fmt.Fprintf(warnings, "warning: listing GitHub stacks failed, showing local stacks only: %v\n", remoteErr)
	}
	if originErr != nil {
		fmt.Fprintf(warnings, "warning: listing origin branches failed, using remote-tracking refs: %v\n", originErr)
	} else {
		refs.remote = originHeads
	}

	return branchCatalog{
		choices:   buildEntries(worktrees, localStacks, remoteStacks, refs),
		worktrees: worktrees,
		refs:      refs,
		stale:     stacksStale || originsStale,
	}, nil
}
