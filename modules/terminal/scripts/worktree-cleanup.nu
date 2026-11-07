#!/usr/bin/env nu

# Interactively remove linked worktrees of the current repo.
#
# `git worktree remove` only deletes the checkout. Bazel keeps a separate
# output_base per workspace path (outside the worktree), plus a server
# process bound to it, so both are cleaned up here as well. The shared
# repository/disk caches are content-addressed and left alone.

def run-or-exit [message: string command: closure] {
  let result = (do $command | complete)

  if ($result.exit_code != 0) {
    let stderr = ($result.stderr | default "" | str trim)
    let detail = if ($stderr | is-empty) { "command failed" } else { $stderr }
    print -e $"($message): ($detail)"
    exit $result.exit_code
  }

  $result.stdout | default ""
}

# Parse `git worktree list --porcelain` into records.
def list-worktrees [] {
  run-or-exit "Unable to list worktrees" {|| ^git worktree list --porcelain }
  | split row "\n\n"
  | where {|block| ($block | str trim) != "" }
  | each {|block|
    let fields = (
      $block
      | lines
      | each {|line|
        let parts = ($line | split row --number 2 " ")
        {key: $parts.0 value: ($parts | get --optional 1 | default "")}
      }
    )
    let get_field = {|key|
      $fields | where key == $key | get --optional 0.value
    }
    let branch = (do $get_field "branch")

    {
      path: (do $get_field "worktree")
      branch: (
        if $branch == null {
          "(detached)"
        } else {
          $branch | str replace "refs/heads/" ""
        }
      )
      locked: (($fields | where key == "locked" | length) > 0)
    }
  }
}

# Resolve the Bazel output_base for a worktree from its convenience symlinks
# (e.g. bazel-out -> <output_base>/execroot/<repo>/bazel-out). Returns null
# when the worktree has never been built with Bazel.
def bazel-output-base [worktree: path] {
  let link = (
    ls --all $worktree
    | where type == symlink and ($it.name | path basename | str starts-with "bazel-")
    | get --optional 0.name
  )
  if $link == null { return null }

  let target = ($link | path expand)
  if not ($target | str contains "/execroot/") { return null }

  let base = ($target | split row "/execroot/" | first)

  # Guard against deleting anything that isn't the output_base for exactly
  # this worktree: Bazel writes the workspace path into README.
  let readme = ($base | path join "README")
  if not ($readme | path exists) { return null }
  let expected = $"WORKSPACE: ($worktree)"
  if not (open --raw $readme | lines | any {|line| $line == $expected }) {
    return null
  }

  $base
}

def stop-bazel-server [worktree: path output_base: path] {
  let pid_file = ($output_base | path join "server" "server.pid.txt")
  if not ($pid_file | path exists) { return }

  if (which bazel | is-not-empty) {
    do { cd $worktree; ^bazel shutdown } | complete | ignore
  }

  # Fall back to killing the server directly if shutdown didn't work.
  if ($pid_file | path exists) {
    let pid = (open --raw $pid_file | str trim)
    if ($pid | is-not-empty) {
      ^kill $pid | complete | ignore
    }
  }
}

def remove-output-base [output_base: path] {
  # Bazel marks much of the output tree read-only.
  ^chmod -R u+w $output_base | complete | ignore
  let result = (^rm -rf $output_base | complete)
  if ($result.exit_code != 0) {
    print -e $"  Failed to remove Bazel output base: ($result.stderr | str trim)"
  } else {
    print $"  Removed Bazel output base ($output_base)"
  }
}

def main [
  --force (-f) # Remove worktrees even if they have uncommitted changes
] {
  run-or-exit "Not inside a git repository" {|| ^git rev-parse --git-dir } | ignore

  let current = (
    run-or-exit "Unable to determine current worktree" {||
      ^git rev-parse --show-toplevel
    }
    | str trim
  )

  # The first entry is always the main worktree, which can't be removed.
  let candidates = (
    list-worktrees
    | skip 1
    | where path != $current
    | each {|wt|
      let output_base = (bazel-output-base $wt.path)
      $wt | insert bazel ($output_base != null) | insert output_base $output_base
    }
  )

  if ($candidates | is-empty) {
    print "No removable worktrees."
    return
  }

  let selected = (
    $candidates
    | select branch path bazel locked
    | input list --multi "Select worktrees to remove"
  )

  if ($selected | is-empty) {
    print "Nothing selected."
    return
  }

  let selected_paths = ($selected | get path)
  for wt in ($candidates | where path in $selected_paths) {
    print $"Removing ($wt.branch) at ($wt.path)"

    if $wt.output_base != null {
      stop-bazel-server $wt.path $wt.output_base
    }

    let args = if $force { [--force] } else { [] }
    let result = (^git worktree remove ...$args $wt.path | complete)
    if ($result.exit_code != 0) {
      print -e $"  Skipping: ($result.stderr | str trim)"
      continue
    }
    print "  Removed worktree"

    if $wt.output_base != null {
      remove-output-base $wt.output_base
    }
  }

  ^git worktree prune | complete | ignore
}
