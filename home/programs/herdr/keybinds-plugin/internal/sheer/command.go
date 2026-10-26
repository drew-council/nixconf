package sheer

import (
	"errors"
	"fmt"

	"github.com/spf13/cobra"

	"herdr-keybinds/internal/fetchcache"
	"herdr-keybinds/internal/herdr"
)

// NewCommand builds the sheer-workspace command for the checkout at root.
// Without --branch it prompts with fzf; with it, the branch is opened or
// created directly.
func NewCommand(root string) *cobra.Command {
	var branch string
	var refresh bool
	mode := func() fetchcache.Mode {
		if refresh {
			return fetchcache.Refresh
		}
		return fetchcache.Fresh
	}
	cmd := &cobra.Command{
		Use:   "sheer-workspace [fzf]",
		Short: "Open or create a sheer worktree workspace",
		Long: "Open or create a sheer worktree workspace for a gh stack or a branch.\n\n" +
			"A branch that belongs to a stack, locally or on GitHub, opens that stack: an\n" +
			"existing worktree on any of its layers is focused, or a new one is created and\n" +
			"the stack is checked out there. Other branches open or create their own worktree,\n" +
			"and unknown names are created from origin/main as a new stack.\n\n" +
			"GitHub stacks and origin branches are cached for " + fetchcache.TTL.String() + " under\n" +
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
				return withRepo(root, func(r *repo) error {
					return r.open(branch, mode())
				})
			}
			fzf := "fzf"
			if len(args) == 1 {
				fzf = args[0]
			}
			return withRepo(root, func(r *repo) error {
				return r.pick(fzf, mode())
			})
		},
	}
	cmd.Flags().StringVarP(&branch, "branch", "b", "", "full branch name to open or create, e.g. drew/my-feature")
	cmd.PersistentFlags().BoolVar(&refresh, "refresh", false,
		"refetch GitHub stacks and origin branches even when cached results are recent")
	cmd.AddCommand(newListCommand(root, mode))
	return cmd
}

// newListCommand prints the stacks and unstacked branches the picker
// offers. The hidden --fzf flag prints the picker's input lines so the picker
// can reload itself through this command.
func newListCommand(root string, mode func() fetchcache.Mode) *cobra.Command {
	var asJSON, asFzf bool
	cmd := &cobra.Command{
		Use:   "list",
		Short: "List stacks and unstacked branches that sheer-workspace can open",
		Long: "List open gh stacks, then branches that belong to no stack, local or on origin.\n" +
			"Pass an entry's branch to `herdrctl sheer-workspace --branch` to open it.",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			format := listText
			switch {
			case asJSON:
				format = listJSON
			case asFzf:
				format = listFzf
			}
			return withRepo(root, func(r *repo) error {
				return r.list(cmd.OutOrStdout(), format, mode())
			})
		},
	}
	cmd.Flags().BoolVar(&asJSON, "json", false, "print entries as JSON")
	cmd.Flags().BoolVar(&asFzf, "fzf", false, "print entries as sheer-workspace picker lines")
	cmd.MarkFlagsMutuallyExclusive("json", "fzf")
	_ = cmd.Flags().MarkHidden("fzf")
	return cmd
}

// withRepo connects to Herdr and runs action against the checkout at root.
func withRepo(root string, action func(*repo) error) error {
	client, err := herdr.NewClient()
	if err != nil {
		return fmt.Errorf("create client: %w", err)
	}
	r, err := newRepo(client, root)
	if err != nil {
		return err
	}
	return action(r)
}
