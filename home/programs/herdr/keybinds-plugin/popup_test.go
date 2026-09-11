package main

import (
	"testing"
)

// Herdr 0.9.0 does not re-apply tab geometry after plugin.pane.open, so an
// overlay keeps the PTY size of the pane it was split from
// (herdrdev/herdr#3799). The helper must focus the new pane to force a resize.
func TestTogglePopupFocusesOpenedOverlay(t *testing.T) {
	t.Setenv("HERDR_PLUGIN_STATE_DIR", t.TempDir())
	t.Setenv("HERDR_WORKSPACE_CWD", "/tmp/ws")
	t.Setenv("HERDR_PANE_ID", "")
	t.Setenv("HERDR_ACTIVE_PANE_ID", "")

	c, requests, stop := newTestClient(t, []testAPIResponse{
		{Result: map[string]any{
			"type": "pane_current",
			"pane": map[string]any{"pane_id": "w1:p1", "workspace_id": "w1"},
		}},
		{Result: map[string]any{"type": "pane_list", "panes": []any{}}},
		{Result: map[string]any{
			"type": "plugin_pane_opened",
			"plugin_pane": map[string]any{
				"plugin_id":  pluginID,
				"entrypoint": "lazygit",
				"pane":       map[string]any{"pane_id": "w1:p9", "workspace_id": "w1"},
			},
		}},
		{Result: map[string]any{
			"type": "pane_info",
			"pane": map[string]any{"pane_id": "w1:p9", "workspace_id": "w1"},
		}},
	})
	defer stop()

	if err := c.togglePopup("lazygit"); err != nil {
		t.Fatalf("togglePopup: %v", err)
	}

	wantMethods := []string{"pane.current", "pane.list", "plugin.pane.open", "pane.focus"}
	if len(*requests) != len(wantMethods) {
		t.Fatalf("got %d requests, want %d: %+v", len(*requests), len(wantMethods), *requests)
	}
	for i, want := range wantMethods {
		if got := (*requests)[i].Method; got != want {
			t.Errorf("request %d method = %q, want %q", i, got, want)
		}
	}
	if got := (*requests)[3].Params["pane_id"]; got != "w1:p9" {
		t.Errorf("pane.focus pane_id = %v, want w1:p9", got)
	}

	state, _, err := loadPluginState()
	if err != nil {
		t.Fatal(err)
	}
	if _, tracked := state.PopupPanes["lazygit"]["w1:p9"]; !tracked {
		t.Errorf("opened overlay not tracked in state: %+v", state.PopupPanes)
	}
}

// Closing the overlay from inside must nudge geometry too: plugin.pane.close
// is not on the server's geometry allow-list either.
func TestTogglePopupRefocusesAfterClose(t *testing.T) {
	t.Setenv("HERDR_PLUGIN_STATE_DIR", t.TempDir())
	t.Setenv("HERDR_PANE_ID", "w1:p9")

	c, requests, stop := newTestClient(t, []testAPIResponse{
		{Result: map[string]any{
			"type": "pane_current",
			"pane": map[string]any{"pane_id": "w1:p9", "workspace_id": "w1", "label": "lazygit"},
		}},
		{Result: map[string]any{"type": "plugin_pane_closed", "pane_id": "w1:p9"}},
		{Result: map[string]any{
			"type": "pane_current",
			"pane": map[string]any{"pane_id": "w1:p1", "workspace_id": "w1"},
		}},
		{Result: map[string]any{
			"type": "pane_info",
			"pane": map[string]any{"pane_id": "w1:p1", "workspace_id": "w1"},
		}},
	})
	defer stop()

	if err := c.togglePopup("lazygit"); err != nil {
		t.Fatalf("togglePopup: %v", err)
	}

	wantMethods := []string{"pane.current", "plugin.pane.close", "pane.current", "pane.focus"}
	if len(*requests) != len(wantMethods) {
		t.Fatalf("got %d requests, want %d: %+v", len(*requests), len(wantMethods), *requests)
	}
	for i, want := range wantMethods {
		if got := (*requests)[i].Method; got != want {
			t.Errorf("request %d method = %q, want %q", i, got, want)
		}
	}
	if got := (*requests)[3].Params["pane_id"]; got != "w1:p1" {
		t.Errorf("pane.focus pane_id = %v, want w1:p1", got)
	}
}
