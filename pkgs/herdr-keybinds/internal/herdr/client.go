// Package herdr is a client for the Herdr socket API, with the API types and
// queries shared by herdrctl's commands.
package herdr

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"

	"herdr-keybinds/internal/xdg"
)

// Client sends JSON RPC requests to the Herdr Unix socket.
type Client struct {
	nextID     int
	socketPath string
}

// APIError is the error object returned by Herdr RPC responses.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Error returns the Herdr API error code and message.
func (err *APIError) Error() string {
	return fmt.Sprintf("%s: %s", err.Code, err.Message)
}

// response is the common envelope returned by Herdr RPC calls.
type response struct {
	ID     string          `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  *APIError       `json:"error"`
}

// NewClient resolves the Herdr socket path and returns a ready RPC client.
func NewClient() (*Client, error) {
	socketPath := os.Getenv("HERDR_SOCKET_PATH")
	if socketPath == "" {
		configDir, err := configDir()
		if err != nil {
			return nil, err
		}
		socketPath = filepath.Join(configDir, "herdr.sock")
	}

	return NewSocketClient(socketPath), nil
}

// NewSocketClient returns a client for the Herdr socket at socketPath.
func NewSocketClient(socketPath string) *Client {
	return &Client{socketPath: socketPath}
}

// Call sends one JSON RPC request to Herdr and decodes its result into out,
// which may be nil when the result is not needed.
func (c *Client) Call(method string, params map[string]any, out any) error {
	payload, id, err := c.encodeRequest(method, params)
	if err != nil {
		return err
	}

	conn, err := c.dial(method)
	if err != nil {
		return err
	}
	defer conn.Close()

	if _, err := conn.Write(payload); err != nil {
		return fmt.Errorf("write %s request: %w", method, err)
	}

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		return fmt.Errorf("read %s response: %w", method, err)
	}

	return decodeResponse(method, id, line, out)
}

// Subscribe streams events of the given types, calling onEvent with each raw
// event line until the stream ends. It always returns an error, since Herdr
// only closes the stream when something went wrong.
func (c *Client) Subscribe(eventTypes []string, onEvent func(line []byte)) error {
	const method = "events.subscribe"
	subscriptions := make([]map[string]string, 0, len(eventTypes))
	for _, eventType := range eventTypes {
		subscriptions = append(subscriptions, map[string]string{"type": eventType})
	}
	payload, id, err := c.encodeRequest(method, map[string]any{
		"subscriptions": subscriptions,
	})
	if err != nil {
		return err
	}

	conn, err := c.dial(method)
	if err != nil {
		return err
	}
	defer conn.Close()

	if _, err := conn.Write(payload); err != nil {
		return fmt.Errorf("write %s request: %w", method, err)
	}

	reader := bufio.NewReader(conn)
	line, err := reader.ReadBytes('\n')
	if err != nil {
		return fmt.Errorf("read %s response: %w", method, err)
	}
	if err := decodeResponse(method, id, line, nil); err != nil {
		return err
	}

	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		onEvent(scanner.Bytes())
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("read Herdr event stream: %w", err)
	}

	return errors.New("Herdr event stream closed")
}

// encodeRequest returns one newline-delimited JSON RPC request payload.
func (c *Client) encodeRequest(method string, params map[string]any) ([]byte, string, error) {
	c.nextID++
	id := fmt.Sprintf("herdr-keybinds-%d", c.nextID)
	if params == nil {
		params = map[string]any{}
	}

	request := map[string]any{
		"id":     id,
		"method": method,
		"params": params,
	}

	payload, err := json.Marshal(request)
	if err != nil {
		return nil, "", fmt.Errorf("encode %s request: %w", method, err)
	}
	payload = append(payload, '\n')
	return payload, id, nil
}

// dial connects to the Herdr socket for one RPC operation.
func (c *Client) dial(method string) (net.Conn, error) {
	dialer := net.Dialer{Timeout: 150 * time.Millisecond}
	conn, err := dialer.Dial("unix", c.socketPath)
	if err != nil {
		return nil, fmt.Errorf("dial Herdr socket %s for %s: %w", c.socketPath, method, err)
	}
	return conn, nil
}

// decodeResponse decodes a JSON RPC response envelope and optional result.
func decodeResponse(method string, id string, line []byte, out any) error {
	var envelope response
	if err := json.Unmarshal(line, &envelope); err != nil {
		return fmt.Errorf("decode %s response: %w", method, err)
	}
	if envelope.Error != nil {
		return envelope.Error
	}
	if envelope.ID != id {
		return fmt.Errorf("unexpected response id %q for %q", envelope.ID, id)
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(envelope.Result, out); err != nil {
		return fmt.Errorf("decode %s result: %w", method, err)
	}

	return nil
}

// sessionPath returns Herdr's persisted session file, next to its socket.
func sessionPath() (string, error) {
	if socketPath := os.Getenv("HERDR_SOCKET_PATH"); socketPath != "" {
		return filepath.Join(filepath.Dir(socketPath), "session.json"), nil
	}
	configDir, err := configDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, "session.json"), nil
}

// configDir returns Herdr's configuration directory.
func configDir() (string, error) {
	if configPath := os.Getenv("HERDR_CONFIG_PATH"); configPath != "" {
		return filepath.Dir(configPath), nil
	}
	configHome, err := xdg.ConfigHome()
	if err != nil {
		return "", err
	}
	return filepath.Join(configHome, "herdr"), nil
}
