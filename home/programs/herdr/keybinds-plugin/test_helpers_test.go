package main

import (
	"testing"

	"herdr-keybinds/internal/herdr/herdrtest"
)

// newTestClient returns a client connected to a scripted Herdr server.
func newTestClient(t *testing.T, responses []herdrtest.Response) (*client, *[]herdrtest.Request, func()) {
	t.Helper()
	herdrClient, requests, stop := herdrtest.NewServer(t, responses)
	return &client{herdrClient}, requests, stop
}
