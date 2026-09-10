#!/usr/bin/env nu

# tables are injected at nix eval time, see ./default.nix
const commands = "@commands@"
const aliases = "@aliases@"

# subcommands implemented here rather than by `gh stack`
const local_commands = [
  {name: "review" description: "Pick stack layers and review their commits in tuicr"}
  {name: "P" description: "Rebase then push the stack"}
]

def pick-subcommand [] {
  let selection = (
    $commands
    | append $local_commands
    | each {|command| $"($command.name)(char tab)($command.description)" }
    | str join "\n"
    | (
      ^fzf
      --prompt "gh stack > "
      --delimiter (char tab)
      --with-nth 1
      --preview "echo {2}"
      --preview-window "right,60%,wrap"
    )
    | complete
  )

  if ($selection.exit_code != 0) {
    exit $selection.exit_code
  }

  $selection.stdout | str trim | split row (char tab) | first
}

# Select one or more layers of the current stack and open their commits in tuicr.
# The stack is linear, so the selection becomes a single `base..head` range covering
# the lowest and highest selected layers.
def stack-review [] {
  let view = (^gh stack view --json | complete)
  if ($view.exit_code != 0) {
    print -e ($view.stderr | str trim)
    exit $view.exit_code
  }
  let stack = ($view.stdout | from json)

  # merged layers already live on trunk, nothing left to review.
  # `head` in the json output is the last recorded head, which lags behind the
  # branch after new commits, so resolve the live tip from the ref instead.
  let layers = (
    $stack.branches
    | where isMerged == false
    | each {|layer|
      let head = (^git rev-parse --verify $"refs/heads/($layer.name)" | str trim)
      {
        branch: $layer.name
        commits: (^git rev-list --count $"($layer.base)..($head)" | into int)
        pr: (
          if ($layer.pr? | is-not-empty) {
            $"#($layer.pr.number) ($layer.pr.state | str lowercase)"
          } else {
            ""
          }
        )
        flags: (
          [
            (if $layer.isCurrent { "current" })
            (if $layer.needsRebase { "needs-rebase" })
            (if $layer.isQueued { "queued" })
          ]
          | compact
          | str join " "
        )
        base: $layer.base
        head: $head
      }
    }
  )

  if ($layers | is-empty) {
    print -e $"no unmerged layers in the stack on ($stack.trunk)"
    return
  }

  let chosen = (
    $layers
    | select branch commits pr flags
    | input list --multi $"layers to review \(stack on ($stack.trunk), bottom first\)"
  )
  if ($chosen | is-empty) {
    return
  }

  # map back to the full layer records, keeping stack order
  let picked = ($layers | where branch in ($chosen | get branch))
  let positions = (
    $layers | enumerate | where item.branch in ($chosen | get branch) | get index
  )
  let span = (($positions | last) - ($positions | first) + 1)
  if ($span != ($positions | length)) {
    print -e "warning: selection is not contiguous, layers in between are included in the review"
  }

  let range = $"(($picked | first).base)..(($picked | last).head)"
  print -e $"reviewing ($picked | get branch | str join ' <- ') \(($range)\)"
  ^tuicr -r $range
}

# --wrapped passes flags like `--short` through to gh stack instead of parsing them
def --wrapped main [...args: string] {
  let args = if ($args | is-empty) { [(pick-subcommand)] } else { $args }

  let subcommand = ($args | first)
  let rest = ($args | skip 1)

  match $subcommand {
    "review" => { stack-review }
    "P" => {
      ^gh stack rebase
      ^gh stack push
    }
    _ => {
      ^gh stack ($aliases | get -o $subcommand | default $subcommand) ...$rest
    }
  }
}
