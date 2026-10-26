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
		newSheerWorkspaceCommand(),
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

// newSheerWorkspaceCommand builds the sheer worktree command. Without --branch
// it prompts with fzf; with it, the branch is opened or created directly.
func newSheerWorkspaceCommand() *cobra.Command {
	var branch string
	var refresh bool
	mode := func() fetchMode {
		if refresh {
			return fetchRefresh
		}
		return fetchFresh
	}
	cmd := &cobra.Command{
		Use:   "sheer-workspace [fzf]",
		Short: "Open or create a sheer worktree workspace",
		Long: "Open or create a sheer worktree workspace for a gh stack or a branch.\n\n" +
			"A branch that belongs to a stack, locally or on GitHub, opens that stack: an\n" +
			"existing worktree on any of its layers is focused, or a new one is created and\n" +
			"the stack is checked out there. Other branches open or create their own worktree,\n" +
			"and unknown names are created from origin/main as a new stack.\n\n" +
			"GitHub stacks and origin branches are cached for " + fetchCacheTTL.String() + " under\n" +
			"$XDG_CACHE_HOME/herdrctl, so repeated calls do not hit GitHub's rate limit.\n" +
			"Older entries are revalidated by ETag. Pass --refresh to revalidate immediately.",
		Example: "  herdrctl sheer-workspace\n" +
			"  herdrctl sheer-workspace list --json\n" +
			"  herdrctl sheer-workspace --branch drew/my-feature",
		Args: cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if cmd.Flags().Changed("branch") {
				if len(args) > 0 {
					return errors.New("fzf argument cannot be combined with --branch")
				}
				return runWithClient(func(c *client) error {
					return c.sheerWorkspaceBranch(branch, mode())
				})
			}
			fzf := "fzf"
			if len(args) == 1 {
				fzf = args[0]
			}
			return runWithClient(func(c *client) error {
				return c.sheerWorkspacePicker(fzf, mode())
			})
		},
	}
	cmd.Flags().StringVarP(&branch, "branch", "b", "", "full branch name to open or create, e.g. drew/my-feature")
	cmd.PersistentFlags().BoolVar(&refresh, "refresh", false,
		"refetch GitHub stacks and origin branches even when cached results are recent")
	cmd.AddCommand(newSheerWorkspaceListCommand(mode))
	return cmd
}

// newSheerWorkspaceListCommand prints the stacks and unstacked branches the
// sheer workspace picker offers. The hidden --fzf flag prints the picker's
// input lines so the picker can reload itself through this command.
func newSheerWorkspaceListCommand(mode func() fetchMode) *cobra.Command {
	var asJSON, asFzf bool
	cmd := &cobra.Command{
		Use:   "list",
		Short: "List stacks and unstacked branches that sheer-workspace can open",
		Long: "List open gh stacks, then branches that belong to no stack, local or on origin.\n" +
			"Pass an entry's branch to `herdrctl sheer-workspace --branch` to open it.",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			format := sheerListText
			switch {
			case asJSON:
				format = sheerListJSON
			case asFzf:
				format = sheerListFzf
			}
			return runWithClient(func(c *client) error {
				return c.sheerWorkspaceList(cmd.OutOrStdout(), format, mode())
			})
		},
	}
	cmd.Flags().BoolVar(&asJSON, "json", false, "print entries as JSON")
	cmd.Flags().BoolVar(&asFzf, "fzf", false, "print entries as sheer-workspace picker lines")
	cmd.MarkFlagsMutuallyExclusive("json", "fzf")
	_ = cmd.Flags().MarkHidden("fzf")
	return cmd
}

// runWithClient creates a Herdr client and runs one command action with it.
func runWithClient(action func(*client) error) error {
	c, err := newClient()
	if err != nil {
		return fmt.Errorf("create client: %w", err)
	}
	return action(c)
}
