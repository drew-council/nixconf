package main

import (
	"reflect"
	"testing"
)

func TestOpenGhst(t *testing.T) {
	t.Setenv("HERDR_PANE_ID", "w1:p1")
	c, requests, stop := newTestClient(t, []testAPIResponse{
		{Result: map[string]any{"pane": paneInfo{PaneID: "w1:p1", CWD: "/repo", ForegroundCWD: "/repo/sub"}}},
		{Result: map[string]any{"pane": paneInfo{PaneID: "w1:p2"}}},
		{Result: map[string]any{}},
		{Result: map[string]any{}},
	})
	defer stop()

	if err := c.openGhst(); err != nil {
		t.Fatal(err)
	}
	want := []testAPIRequest{
		{Method: "pane.current", Params: map[string]any{"caller_pane_id": "w1:p1"}},
		{Method: "pane.split", Params: map[string]any{
			"target_pane_id": "w1:p1", "direction": "right", "ratio": ghstLeftPaneRatio,
			"cwd": "/repo/sub", "focus": true,
		}},
		{Method: "pane.send_text", Params: map[string]any{"pane_id": "w1:p2", "text": "ghst"}},
		{Method: "pane.send_keys", Params: map[string]any{"pane_id": "w1:p2", "keys": []any{"enter"}}},
	}
	if len(*requests) != len(want) {
		t.Fatalf("got %d requests, want %d", len(*requests), len(want))
	}
	for i, request := range *requests {
		if request.Method != want[i].Method || !reflect.DeepEqual(request.Params, want[i].Params) {
			t.Errorf("request %d: got %s %v, want %s %v", i, request.Method, request.Params, want[i].Method, want[i].Params)
		}
	}
}
