package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"herdr-keybinds/internal/herdr"
)

var lazygitWatchEvents = []string{
	"workspace.created",
	"workspace.focused",
	"pane.focused",
}

type lazygitProcess struct {
	cmd  *exec.Cmd
	done chan error
}

// watchLazygit runs one lazygit process in the active Herdr workspace root and
// restarts it whenever Herdr focuses a workspace with a different root.
func watchLazygit(lazygit string) error {
	queryClient, err := herdr.NewClient()
	if err != nil {
		return fmt.Errorf("create query client: %w", err)
	}
	eventClient, err := herdr.NewClient()
	if err != nil {
		return fmt.Errorf("create event client: %w", err)
	}

	cwd, err := activeLazygitCWD(queryClient)
	if err != nil {
		return err
	}

	events := make(chan struct{}, 4)
	subscribeDone := make(chan error, 1)
	go func() {
		subscribeDone <- eventClient.Subscribe(lazygitWatchEvents, func(line []byte) {
			if lazygitWatchEventLine(line) {
				select {
				case events <- struct{}{}:
				default:
				}
			}
		})
	}()

	child, err := startLazygitProcess(lazygit, cwd)
	if err != nil {
		showLazygitWatchError(cwd, err)
	}
	var childDone <-chan error
	if child != nil {
		childDone = child.done
	}

	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGHUP, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(signals)

	for {
		select {
		case <-events:
			var err error
			child, cwd, err = restartLazygitIfCWDChanged(queryClient, child, lazygit, cwd)
			if err != nil {
				showLazygitWatchError(cwd, err)
				child = nil
			}
			childDone = nil
			if child != nil {
				childDone = child.done
			}
		case <-ticker.C:
			var err error
			child, cwd, err = restartLazygitIfCWDChanged(queryClient, child, lazygit, cwd)
			if err != nil {
				showLazygitWatchError(cwd, err)
				child = nil
			}
			childDone = nil
			if child != nil {
				childDone = child.done
			}
		case err := <-childDone:
			if err == nil {
				return nil
			}
			showLazygitWatchError(cwd, err)
			child = nil
			childDone = nil
		case err := <-subscribeDone:
			_ = child.stop(2 * time.Second)
			return err
		case <-signals:
			return child.stop(2 * time.Second)
		}
	}
}

func restartLazygitIfCWDChanged(c *herdr.Client, child *lazygitProcess, lazygit string, cwd string) (*lazygitProcess, string, error) {
	nextCWD, err := activeLazygitCWD(c)
	if err != nil || samePath(cwd, nextCWD) {
		return child, cwd, nil
	}
	if err := child.stop(2 * time.Second); err != nil {
		return child, cwd, err
	}
	nextChild, err := startLazygitProcess(lazygit, nextCWD)
	if err != nil {
		return nil, nextCWD, err
	}
	return nextChild, nextCWD, nil
}

func showLazygitWatchError(cwd string, err error) {
	fmt.Fprint(os.Stdout, "\x1b[2J\x1b[H")
	fmt.Fprintln(os.Stdout, "lazygit exited with an error")
	fmt.Fprintln(os.Stdout)
	if cwd != "" {
		fmt.Fprintf(os.Stdout, "workspace: %s\n", cwd)
	}
	fmt.Fprintf(os.Stdout, "error: %v\n", err)
	fmt.Fprintln(os.Stdout)
	fmt.Fprintln(os.Stdout, "lg-herdr-watch is still running; switch workspaces to retry.")
}

// activeLazygitCWD returns the root directory of Herdr's focused workspace.
func activeLazygitCWD(c *herdr.Client) (string, error) {
	workspace, err := focusedWorkspace(c)
	if err != nil {
		return "", fmt.Errorf("resolve active Herdr workspace: %w", err)
	}
	if workspace.WorkspaceID == "" {
		return "", errors.New("could not resolve active Herdr workspace")
	}

	cwd, err := herdr.WorkspaceIdentityCWD(workspace.WorkspaceID)
	if err != nil {
		return "", fmt.Errorf("resolve active Herdr workspace cwd: %w", err)
	}
	if cwd == "" {
		return "", errors.New("could not resolve active Herdr workspace cwd")
	}
	return filepath.Clean(cwd), nil
}

// focusedWorkspace returns Herdr's focused workspace, or a zero value when
// none is focused.
func focusedWorkspace(c *herdr.Client) (herdr.Workspace, error) {
	workspaces, err := c.Workspaces()
	if err != nil {
		return herdr.Workspace{}, err
	}
	for _, workspace := range workspaces {
		if workspace.Focused {
			return workspace, nil
		}
	}
	return herdr.Workspace{}, nil
}

func lazygitWatchEventLine(line []byte) bool {
	for _, eventName := range lazygitWatchEvents {
		if bytes.Contains(line, []byte(eventName)) {
			return true
		}
	}
	return false
}

func startLazygitProcess(lazygit string, cwd string) (*lazygitProcess, error) {
	cmd := exec.Command(lazygit)
	cmd.Dir = cwd
	cmd.Env = os.Environ()
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start lazygit in %s: %w", cwd, err)
	}

	child := &lazygitProcess{
		cmd:  cmd,
		done: make(chan error, 1),
	}
	go func() {
		child.done <- cmd.Wait()
	}()
	return child, nil
}

func (child *lazygitProcess) stop(timeout time.Duration) error {
	if child == nil || child.cmd == nil || child.cmd.Process == nil {
		return nil
	}

	if err := child.cmd.Process.Signal(syscall.SIGTERM); err != nil && !errors.Is(err, os.ErrProcessDone) {
		return fmt.Errorf("stop lazygit: %w", err)
	}

	select {
	case <-child.done:
		return nil
	case <-time.After(timeout):
		if err := child.cmd.Process.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
			return fmt.Errorf("kill lazygit: %w", err)
		}
		<-child.done
		return nil
	}
}

func samePath(left string, right string) bool {
	if left == "" || right == "" {
		return left == right
	}
	return filepath.Clean(left) == filepath.Clean(right)
}
