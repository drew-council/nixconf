#!/usr/bin/env nu

# tables are injected at nix eval time, see ./default.nix
const commands = "@commands@"
const aliases = "@aliases@"

# subcommands implemented here rather than by `gh stack`
const local_commands = [
  {name: "review" description: "Pick stack layers and review their commits in tuicr"}
  {name: "P" description: "Sync the stack, pruning merged branches"}
  {name: "pull" description: "Make the local stack match GitHub, without rebasing or pushing"}
]

def fail [message: string] {
  print -e $message
  exit 1
}

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
    # listed top first to match `gh stack view`, with the bottom of the stack last
    $layers
    | reverse
    | select branch commits pr flags
    | input list --multi $"layers to review \(stack on ($stack.trunk), top first\)"
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

# Run gh stack with stdout piped, which keeps it from prompting
def --wrapped gh-stack [...args: string] {
  let result = (^gh stack ...$args | complete)
  if ($result.exit_code != 0) {
    print -e ([$result.stderr $result.stdout] | str join "\n" | str trim)
    exit $result.exit_code
  }
  $result
}

# The remote gh stack fetches from, which it needs to be unambiguous
def stack-remote [] {
  let configured = (^git config --get remote.pushDefault | complete)
  if ($configured.exit_code == 0) {
    return ($configured.stdout | str trim)
  }
  let remotes = (^git remote | lines)
  if (($remotes | length) != 1) {
    fail "set remote.pushDefault, gh stack cannot pick between several remotes"
  }
  $remotes | first
}

# GET a path under the repository's Stacks REST API, or null when it is not found
def stacks-api [path: string] {
  let response = (^gh api $"repos/{owner}/{repo}/($path)" | complete)
  if ($response.exit_code == 0) {
    return ($response.stdout | from json)
  }
  if ($response.stderr | str contains "HTTP 404") {
    return null
  }
  fail ($response.stderr | str trim)
}

# Find the stack on GitHub holding a PR, falling back to the stack with that
# number, since stacks and PRs share one numberspace
def stack-by-number [number: int] {
  let stacks = (stacks-api $"stacks?pull_request=($number)")
  if ($stacks | is-not-empty) {
    # a PR can sit in a closed stack and in the open one that replaced it
    return ($stacks | where open == true | append $stacks | first)
  }
  stacks-api $"stacks/($number)"
}

# Stacks tracked locally, from the catalog gh stack shares across worktrees
def local-stacks [] {
  let catalog = (
    ^git rev-parse --path-format=absolute --git-common-dir | str trim | path join "gh-stack"
  )
  if not ($catalog | path exists) {
    return []
  }
  open --raw $catalog | from json | get stacks
}

# Find the stack on GitHub for a stack number, PR number, PR URL, or branch.
# A branch is looked up through its own PRs, then the PRs of its local stack,
# because the local stack's number goes stale when GitHub recreates the stack.
def find-remote-stack [target: string] {
  let number = (
    $target | parse --regex '^(?:https://\S+/pull/)?(?<number>\d+)/?$' | get -o 0.number
  )
  if ($number != null) {
    return (stack-by-number ($number | into int))
  }
  let local_prs = (
    local-stacks
    | where {|local| $target in $local.branches.branch? }
    | each {|local| $local.branches | each {|branch| $branch.pullRequest?.number? } }
    | flatten
  )
  let candidates = (
    ^gh pr list --head $target --state all --json number --jq '.[].number'
    | lines
    | into int
    | append $local_prs
    | compact
    | uniq
  )
  for candidate in $candidates {
    let found = (stack-by-number $candidate)
    if ($found != null) {
      return $found
    }
  }
  null
}

# Branches checked out in a worktree, with the worktree's path
def worktree-branches [] {
  ^git worktree list --porcelain
  | split row "\n\n"
  | each {|entry|
    let fields = ($entry | lines | parse "{key} {value}")
    {
      path: ($fields | where key == worktree | get -o 0.value)
      branch: (
        $fields
        | where key == branch
        | get -o 0.value
        | default ""
        | str replace --regex '^refs/heads/' ''
      )
    }
  }
  | where branch != ""
}

# How pulling moves a branch from its local commit to its target commit
def branch-change [local: string target?: string] {
  if ($target == null) {
    return "skip, merged and deleted"
  }
  if ($local | is-empty) {
    return "create"
  }
  if ($local == $target) {
    return "none"
  }
  if ((^git merge-base --is-ancestor $local $target | complete).exit_code == 0) {
    return "fast-forward"
  }
  # commits with no equivalent on GitHub, which only the backup keeps
  let unique = (
    ^git rev-list --count --left-only --cherry-pick $"($local)...($target)" | into int
  )
  if ($unique == 0) { "reset" } else { $"reset, ($unique) not on GitHub" }
}

# Make the local stack match its stack on GitHub. Branches move to their remote
# tips, missing layers are created, and local tracking is imported again.
# Nothing is rebased or pushed, so GitHub stays as it is.
# The target is a stack number, PR number, PR URL, or branch, and defaults to
# the current branch.
def stack-pull [target?: string --dry-run] {
  let current = (^git branch --show-current | str trim)
  let target = ($target | default $current)
  if ($target | is-empty) {
    fail "HEAD is detached, pass a stack number, PR, or branch"
  }
  let stack = (find-remote-stack $target)
  if ($stack == null) {
    fail $"no stack on GitHub contains ($target)"
  }
  if not $stack.open {
    fail $"every PR in stack #($stack.number) is merged"
  }

  let remote = (stack-remote)
  let prs = $stack.pull_requests
  let names = ($prs | get head.ref)
  let on_remote = (
    ^git ls-remote --heads $remote ...$names
    | lines
    | parse "{sha}\t{ref}"
    | where ref in ($names | each {|name| $"refs/heads/($name)" })
    | get ref
    | str replace --regex '^refs/heads/' ''
  )
  # a closed PR whose branch was deleted is only reachable through its PR ref
  let orphans = (
    $prs | where {|pr| $pr.head.ref not-in $on_remote and $pr.merged_at == null }
  )
  let refspecs = (
    $on_remote
    | each {|branch| $"+refs/heads/($branch):refs/remotes/($remote)/($branch)" }
    | append ($orphans | each {|pr| $"refs/pull/($pr.number)/head" })
  )
  ^git fetch --quiet $remote ...$refspecs

  let worktrees = (worktree-branches)
  let plan = (
    $prs
    | each {|pr|
      let branch = $pr.head.ref
      # gh stack skips merged PRs whose branch was deleted
      let start = if $branch in $on_remote {
        $"refs/remotes/($remote)/($branch)"
      } else if $pr.merged_at == null {
        $pr.head.sha
      }
      let target = if $start != null {
        ^git rev-parse --verify $"($start)^{commit}" | str trim
      }
      let local = (
        ^git rev-parse --verify --quiet $"refs/heads/($branch)" | complete | get stdout | str trim
      )
      {
        branch: $branch
        pr: $pr.number
        merged: ($pr.merged_at != null)
        local: $local
        target: $target
        start: $start
        worktree: ($worktrees | where branch == $branch | get -o 0.path)
        change: (branch-change $local $target)
      }
    }
  )
  let moves = ($plan | where {|row| $row.target != null and $row.local != $row.target })
  let overlapping = (
    local-stacks | where {|local| $local.branches.branch? | any {|branch| $branch in $names } }
  )
  let unstacked = (
    $overlapping | each {|local| $local.branches.branch? } | flatten | where $it not-in $names | uniq
  )

  print $"stack #($stack.number) on ($stack.base.ref), top first"
  print ($plan | reverse | select branch pr change)
  for pr in $orphans {
    print $"#($pr.number) is closed and its branch is gone from ($remote), so it comes from the PR head"
  }
  if ($unstacked | is-not-empty) {
    print $"no longer stacked, local branches kept: ($unstacked | str join ', ')"
  }

  let dirty = (
    $moves
    | where worktree != null
    | where {|row| ^git -C $row.worktree status --porcelain --untracked-files=no | is-not-empty }
  )
  if ($dirty | is-not-empty) {
    fail $"commit or stash the changes in ($dirty | get worktree | uniq | str join ', ')"
  }
  # gh stack can only untrack a stack without a number from one of its branches
  let stranded = (
    $overlapping | where {|local| $local.number? == null and $current not-in $local.branches.branch? }
  )
  if ($stranded | is-not-empty) {
    let chains = ($stranded | each {|local| $local.branches.branch? | str join " <- " })
    fail $"run `gh stack unstack --local` from a branch of: ($chains | str join '; ')"
  }
  if $dry_run {
    return
  }

  let backup = $"refs/backup/gs-pull/(date now | format date '%Y%m%dT%H%M%S')"
  for row in ($moves | where {|row| $row.local | is-not-empty }) {
    ^git update-ref $"($backup)/($row.branch)" $row.local
  }
  for row in $moves {
    # git will not move a branch out from under its worktree, so switch it there
    if ($row.worktree != null) {
      ^git -C $row.worktree switch --quiet --force-create $row.branch $row.start
    } else {
      ^git branch --quiet --force $row.branch $row.start
    }
  }

  # checkout only creates branches that are missing, so importing after the
  # branches move records their new heads
  for local in ($overlapping | where {|local| $local.number? != null }) {
    gh-stack unstack --local ($local.number | into string)
  }
  if ($overlapping | any {|local| $local.number? == null }) {
    gh-stack unstack --local
  }
  # checking out the current branch's own PR keeps it checked out
  let checkout = if $current in $names {
    $plan | where branch == $current | first | get pr
  } else {
    $stack.number
  }
  print -e (gh-stack checkout ($checkout | into string) | get stderr | str trim)

  let view = (gh-stack view --json | get stdout | from json)
  let stale = (
    $plan
    | where {|row| $row.target != null and not $row.merged }
    | where {|row| ($view.branches | where name == $row.branch | get -o 0.head) != $row.target }
  )
  if (($view.branches | get name) != $names or ($stale | is-not-empty)) {
    print -e "warning: local tracking still differs from GitHub, see `gh stack view`"
  }
  if ($moves | any {|row| $row.local | is-not-empty }) {
    print $"previous branch tips are saved under ($backup)"
  }
  let behind = ($view.branches | where needsRebase == true | get name)
  if ($behind | is-not-empty) {
    print $"needs a rebase, left alone so GitHub stays as it is: ($behind | str join ', ')"
  }
}

# --wrapped passes flags like `--short` through to gh stack instead of parsing them
def --wrapped main [...args: string] {
  let args = if ($args | is-empty) { [(pick-subcommand)] } else { $args }

  let subcommand = ($args | first)
  let rest = ($args | skip 1)

  match $subcommand {
    "review" => { stack-review }
    "P" => { ^gh stack sync --prune }
    "pull" => {
      let flags = ["--dry-run" "-n"]
      stack-pull ($rest | where $it not-in $flags | get -o 0) --dry-run=($rest | any {|arg| $arg in $flags })
    }
    _ => {
      ^gh stack ($aliases | get -o $subcommand | default $subcommand) ...$rest
    }
  }
}
