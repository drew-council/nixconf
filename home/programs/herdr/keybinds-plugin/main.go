// Package main implements the herdr-keybinds helper CLI.
package main

import (
	"errors"
	"fmt"
	"log/slog"
	"os"

	"github.com/spf13/cobra"
)

var logger = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
	ReplaceAttr: func(_ []string, attr slog.Attr) slog.Attr {
		if attr.Key == slog.TimeKey {
			return slog.Attr{}
		}
		return attr
	},
}))

// main builds the CLI and logs any command failure in structured form.
func main() {
	rootCmd := newRootCommand()
	if err := rootCmd.Execute(); err != nil {
		logger.Error("command failed", "error", err)
		os.Exit(1)
	}
}

// newRootCommand wires every keybinding action into the Cobra command tree.
func newRootCommand() *cobra.Command {
	rootCmd := &cobra.Command{
		Use:           "herdrctl",
		Short:         "Control Herdr extensions from the command line",
		Args:          cobra.NoArgs,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			cmd.SilenceUsage = true
			if err := cmd.Help(); err != nil {
				return err
			}
			return errors.New("missing command")
		},
	}

	rootCmd.AddCommand(
		&cobra.Command{
			Use:       "navigate <left|right|up|down>",
			Short:     "Navigate to a neighboring pane, tab, or workspace",
			Args:      cobra.MatchAll(cobra.ExactArgs(1), cobra.OnlyValidArgs),
			ValidArgs: []string{"left", "right", "up", "down"},
			RunE: func(_ *cobra.Command, args []string) error {
				dir, _ := parseDirection(args[0])
				return runWithClient(func(c *client) error {
					return c.navigate(dir)
				})
			},
		},
		&cobra.Command{
			Use:   "focus-tab <label>",
			Short: "Focus the tab with the given label",
			Args:  cobra.ExactArgs(1),
			RunE: func(_ *cobra.Command, args []string) error {
				return runWithClient(func(c *client) error {
					return c.focusTabLabel(args[0])
				})
			},
		},
		&cobra.Command{
			Use:   "open-ghst",
			Short: "Open ghst in a narrow pane to the right",
			Args:  cobra.NoArgs,
			RunE: func(_ *cobra.Command, _ []string) error {
				return runWithClient(func(c *client) error {
					return c.openGhst()
				})
			},
		},
		&cobra.Command{
			Use:   "toggle-popup <name>",
			Short: "Toggle a configured popup overlay pane",
			Args:  cobra.ExactArgs(1),
			RunE: func(_ *cobra.Command, args []string) error {
				return runWithClient(func(c *client) error {
					return c.togglePopup(args[0])
				})
			},
		},
		&cobra.Command{
			Use:    "toggle-lazygit",
			Short:  "Toggle the lazygit overlay pane",
			Args:   cobra.NoArgs,
			Hidden: true,
			RunE: func(_ *cobra.Command, _ []string) error {
				return runWithClient(func(c *client) error {
					return c.togglePopup("lazygit")
				})
			},
		},
		&cobra.Command{
			Use:   "watch-lazygit [lazygit]",
			Short: "Run lazygit and restart it when the focused Herdr workspace changes",
			Args:  cobra.MaximumNArgs(1),
			RunE: func(_ *cobra.Command, args []string) error {
				lazygit := "lazygit"
				if len(args) == 1 {
					lazygit = args[0]
				}
				return watchLazygit(lazygit)
			},
		},
		&cobra.Command{
			Use:   "open-workspace [fzf]",
			Short: "Choose a directory and open or focus its workspace",
			Args:  cobra.MaximumNArgs(1),
			RunE: func(_ *cobra.Command, args []string) error {
				fzf := "fzf"
				if len(args) == 1 {
					fzf = args[0]
				}
				return runWithClient(func(c *client) error {
					return c.newWorkspacePicker(fzf)
				})
			},
		},
		&cobra.Command{
			Use:   "sheer-workspace [fzf]",
			Short: "Open or create a sheer worktree workspace",
			Args:  cobra.MaximumNArgs(1),
			RunE: func(_ *cobra.Command, args []string) error {
				fzf := "fzf"
				if len(args) == 1 {
					fzf = args[0]
				}
				return runWithClient(func(c *client) error {
					return c.sheerWorkspacePicker(fzf)
				})
			},
		},
		&cobra.Command{
			Use:    "open-workspace-popup",
			Short:  "Open the workspace picker in a popup pane",
			Args:   cobra.NoArgs,
			Hidden: true,
			RunE: func(_ *cobra.Command, _ []string) error {
				return runWithClient(func(c *client) error {
					return c.openWorkspacePicker()
				})
			},
		},
		&cobra.Command{
			Use:    "sheer-workspace-popup",
			Short:  "Open the sheer worktree picker in a popup pane",
			Args:   cobra.NoArgs,
			Hidden: true,
			RunE: func(_ *cobra.Command, _ []string) error {
				return runWithClient(func(c *client) error {
					return c.openSheerWorkspacePicker()
				})
			},
		},
	)

	return rootCmd
}

// runWithClient creates a Herdr client and runs one command action with it.
func runWithClient(action func(*client) error) error {
	c, err := newClient()
	if err != nil {
		return fmt.Errorf("create client: %w", err)
	}
	return action(c)
}
