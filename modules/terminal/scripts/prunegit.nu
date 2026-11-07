#!/usr/bin/env nu

# Delete local branches that no longer exist on the default remote.
# Use `complete` for external commands so Nushell doesn't abort with a
# pipeline error when git exits non-zero (for example, unmerged branches).

def git-lines [message: string command: closure] {
  let result = (do $command | complete)

  if ($result.exit_code != 0) {
    let stderr = ($result.stderr | default "" | str trim)
    let detail = if ($stderr | is-empty) { "git command failed" } else { $stderr }
    print -e $"($message): ($detail)"
    exit $result.exit_code
  }

  $result.stdout | default "" | lines
}

let local = (
  git-lines "Unable to list local branches" {||
    ^git for-each-ref --format='%(refname:short)' refs/heads/
  }
)

let remote = (
  git-lines "Unable to list remote branches" {||
    ^git ls-remote --heads
  } | each {|line|
    $line | split row "\trefs/heads/" | get 1
  }
)

let current = (
  git-lines "Unable to determine current branch" {||
    ^git branch --show-current
  }
  | first
  | default ""
)

let no_upstream = (
  $local
  | where {|branch| $branch != $current and not ($branch in $remote) }
)

if ($no_upstream | is-empty) {
  print "No local branches to remove."
  exit 0
}

print "About to remove the following branches:"
print $no_upstream
try {
  input "Press enter to continue..."
} catch {
  print -e "Confirmation cancelled."
  exit 1
}

$no_upstream | each {|branch|
  let result = (^git branch -d $branch | complete)

  if ($result.exit_code == 0) {
    print ($result.stdout | default "" | str trim)
  } else {
    let stderr = ($result.stderr | default "" | str trim)
    print $"Skipping ($branch): ($stderr)"
  }
} | ignore
