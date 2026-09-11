package main

import "testing"

func TestFallbackWorkspaceFollowsSidebarWorktreeOrder(t *testing.T) {
	workspaceList := func() map[string]any {
		return map[string]any{
			"type": "workspace_list",
			"workspaces": []any{
				map[string]any{
					"number":       1,
					"workspace_id": "nixconf",
					"worktree": map[string]any{
						"is_linked_worktree": false,
						"repo_key":           "/work/nixconf/.git",
					},
				},
				map[string]any{
					"number":       2,
					"workspace_id": "pi",
				},
				map[string]any{
					"number":       3,
					"workspace_id": "macos",
					"worktree": map[string]any{
						"is_linked_worktree": true,
						"repo_key":           "/work/nixconf/.git",
					},
				},
			},
		}
	}

	client, requests, stop := newTestClient(t, []testAPIResponse{
		{Result: workspaceList()},
		{Result: map[string]any{"type": "workspace_focused"}},
		{Result: workspaceList()},
		{Result: map[string]any{"type": "workspace_focused"}},
		{Result: workspaceList()},
		{Result: map[string]any{"type": "workspace_focused"}},
	})
	defer stop()

	moves := []struct {
		from      string
		direction Direction
		want      string
	}{
		{from: "nixconf", direction: directionDown, want: "macos"},
		{from: "macos", direction: directionDown, want: "pi"},
		{from: "pi", direction: directionUp, want: "macos"},
	}
	for _, move := range moves {
		if err := client.fallbackWorkspace(
			context{WorkspaceID: move.from},
			move.direction,
		); err != nil {
			t.Fatal(err)
		}
	}

	for index, move := range moves {
		request := (*requests)[index*2+1]
		if request.Method != "workspace.focus" {
			t.Fatalf("move %d method = %q, want workspace.focus", index, request.Method)
		}
		if got := request.Params["workspace_id"]; got != move.want {
			t.Fatalf("move from %s focused %#v, want %s", move.from, got, move.want)
		}
	}
}
