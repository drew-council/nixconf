package herdr

import "sort"

// sortByPosition orders Herdr objects by their user-visible number.
func sortByPosition[T Focusable](items []T) {
	sort.Slice(items, func(i, j int) bool {
		return items[i].Position() < items[j].Position()
	})
}

// sidebarOrder matches the sidebar's repository grouping. Herdr numbers
// workspaces globally, but renders linked worktrees immediately after their
// main checkout rather than at that global position.
func sidebarOrder(items []Workspace) []Workspace {
	sorted := append([]Workspace(nil), items...)
	sortByPosition(sorted)

	roots := make(map[string]Workspace)
	for _, workspace := range sorted {
		if workspace.Worktree != nil &&
			workspace.Worktree.RepoKey != "" &&
			!workspace.Worktree.IsLinkedWorktree {
			roots[workspace.Worktree.RepoKey] = workspace
		}
	}

	ordered := make([]Workspace, 0, len(sorted))
	emittedRepos := make(map[string]bool)
	for _, workspace := range sorted {
		if workspace.Worktree == nil || workspace.Worktree.RepoKey == "" {
			ordered = append(ordered, workspace)
			continue
		}

		repoKey := workspace.Worktree.RepoKey
		if emittedRepos[repoKey] {
			continue
		}
		if root, ok := roots[repoKey]; ok {
			if root.WorkspaceID != workspace.WorkspaceID {
				continue
			}
			ordered = append(ordered, root)
		}
		emittedRepos[repoKey] = true
		for _, candidate := range sorted {
			if candidate.Worktree != nil &&
				candidate.Worktree.RepoKey == repoKey &&
				candidate.Worktree.IsLinkedWorktree {
				ordered = append(ordered, candidate)
			}
		}
	}

	return ordered
}
