// Package herdrtest serves scripted Herdr socket API responses for tests.
package herdrtest

import (
	"bufio"
	"encoding/json"
	"net"
	"path/filepath"
	"testing"

	"herdr-keybinds/internal/herdr"
)

// Response is one scripted reply. Result is encoded as the response's result
// unless Error is set.
type Response struct {
	Result any
	Error  *herdr.APIError
}

// Request is one request the server received, with params decoded from JSON
// so numbers are float64 and lists are []any.
type Request struct {
	ID     string         `json:"id"`
	Method string         `json:"method"`
	Params map[string]any `json:"params"`
}

// NewServer listens on a temporary socket and answers one request per
// response, in order. It returns a client for the socket, the requests
// received so far, and a stop function that waits for the server to exit.
func NewServer(t *testing.T, responses []Response) (*herdr.Client, *[]Request, func()) {
	t.Helper()

	socketPath := filepath.Join(t.TempDir(), "herdr.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}

	requests := make([]Request, 0, len(responses))
	done := make(chan struct{})
	go func() {
		defer close(done)
		defer listener.Close()

		for _, response := range responses {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			serve(t, conn, response, &requests)
		}
	}()

	stop := func() {
		listener.Close()
		<-done
	}
	return herdr.NewSocketClient(socketPath), &requests, stop
}

// serve answers the single request sent on conn.
func serve(t *testing.T, conn net.Conn, scripted Response, requests *[]Request) {
	t.Helper()
	defer conn.Close()

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		t.Error(err)
		return
	}

	var request Request
	if err := json.Unmarshal(line, &request); err != nil {
		t.Error(err)
		return
	}
	*requests = append(*requests, request)

	result, err := json.Marshal(scripted.Result)
	if err != nil {
		t.Error(err)
		return
	}
	payload, err := json.Marshal(struct {
		ID     string          `json:"id"`
		Result json.RawMessage `json:"result"`
		Error  *herdr.APIError `json:"error"`
	}{ID: request.ID, Result: result, Error: scripted.Error})
	if err != nil {
		t.Error(err)
		return
	}
	payload = append(payload, '\n')
	if _, err := conn.Write(payload); err != nil {
		t.Error(err)
	}
}
