// Package pending tracks the one queued `switchaudio --wait` request.
//
// A request owns the switch while its ID is in the pending file.
// Any newer invocation replaces or removes the ID,
// which cancels the older request at its next attempt.
package pending

import (
	"crypto/rand"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

const (
	fileName = "switchaudio-pending"
	lockName = "switchaudio-pending.lock"
)

// Store keeps the pending request in Dir.
type Store struct {
	Dir string
}

// RuntimeStore returns a Store in $XDG_RUNTIME_DIR, or /tmp when unset.
func RuntimeStore() Store {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = "/tmp"
	}
	return Store{Dir: dir}
}

func (s Store) path() string { return filepath.Join(s.Dir, fileName) }

// Lock takes the exclusive lock that guards the pending file.
func (s Store) Lock() (unlock func(), err error) {
	f, err := os.OpenFile(filepath.Join(s.Dir, lockName), os.O_RDWR|os.O_CREATE|os.O_APPEND, 0o666)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, err
	}
	return func() {
		syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}

// Read returns the pending request ID, or "" when none is pending.
// The caller MUST hold the lock.
func (s Store) Read() (string, error) {
	data, err := os.ReadFile(s.path())
	if errors.Is(err, fs.ErrNotExist) {
		return "", nil
	}
	return strings.TrimSpace(string(data)), err
}

// Remove deletes the pending file.
// The caller MUST hold the lock.
func (s Store) Remove() error {
	err := os.Remove(s.path())
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	return err
}

// Queue records a new request, replacing any pending one,
// and returns its ID.
func (s Store) Queue() (string, error) {
	id := rand.Text()
	unlock, err := s.Lock()
	if err != nil {
		return "", err
	}
	defer unlock()
	return id, os.WriteFile(s.path(), []byte(id+"\n"), 0o666)
}

// Clear removes the pending request.
// A non-empty id only removes that request.
func (s Store) Clear(id string) error {
	unlock, err := s.Lock()
	if err != nil {
		return err
	}
	defer unlock()
	if id != "" {
		current, err := s.Read()
		if err != nil {
			return err
		}
		if current != id {
			return nil
		}
	}
	return s.Remove()
}
