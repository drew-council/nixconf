# Bazel writes the workspace path into DO_NOT_BUILD_HERE in every output base,
# and each worktree gets its own output base, so deleting a worktree strands an
# output base of several GiB. Nothing else ever reclaims them: 20 stranded bases
# once filled ~150 GiB. Bazel never shrinks a live worktree's base either: one
# that has run the Go tests holds ~25 GiB of go_test binaries (one per _test.go
# file) indefinitely. This walks the output_user_root and removes bases whose
# workspace is gone or that no command has used in --max-idle-hours. Bazel 9
# clones disk-cache hits into the output base, so rebuilding a pruned worktree
# costs clones rather than a full build while the disk cache still holds them.
#
# Agent worktrees made a 3-day window useless: 37 bases (~415 GiB) built up in
# one day and filled a 500 GB disk. --max-used-percent also deletes idle bases,
# least recently used first, while the disk stays above that usage.
{
  lib,
  nushell,
  writeScriptBin,
  # Must match --output_user_root in the .bazelrc.
  outputUserRoot ? "/var/tmp/_bazel",
}:
writeScriptBin "bazelprune" ''
  #!${lib.getExe nushell}

  # Percent of the filesystem holding path that is in use.
  def used-percent [path: string]: nothing -> int {
    # XFS frees unlinked blocks in the background; let df see them.
    ^sync
    let row = (^df -Pk $path | lines | last | split row --regex '\s+')
    let used = ($row | get 2 | into int)
    let avail = ($row | get 3 | into int)
    ($used * 100 / ($used + $avail)) | math ceil
  }

  def prune-base [base: string, reason: string, dry_run: bool] {
    print $"($base): ($reason)"
    if not $dry_run {
      # Bazel marks parts of the output tree read-only.
      ^chmod -R u+w $base
      rm --recursive --force --permanent $base
    }
  }

  # Delete Bazel output bases whose workspace directory no longer exists, or
  # that have not been used in --max-idle-hours. While the disk is above
  # --max-used-percent, also delete the remaining idle bases, least recently
  # used first.
  def main [
    --dry-run
    --max-idle-hours: int = 12
    --max-used-percent: int = 100
  ] {
    let root = "${outputUserRoot}"
    if not ($root | path exists) {
      return
    }
    let cutoff = ((date now) - ($max_idle_hours * 1hr))

    let idle = (
      ls $root
      | where type == dir
      | each {|entry|
          let marker = ($entry.name | path join "DO_NOT_BUILD_HERE")
          if not ($marker | path exists) { return null }
          let workspace = (open --raw $marker | str trim)
          # Never pull an output base out from under a live server. A server
          # exits after --max_idle_secs (3h), so a live one was used recently.
          let pid_file = ($entry.name | path join "server" "server.pid.txt")
          let pid = if ($pid_file | path exists) { open --raw $pid_file | str trim } else { "" }
          if ($pid | is-not-empty) and (do { ^kill -0 $pid } | complete | get exit_code) == 0 {
            return null
          }
          # Every command writes a profile and takes the lock at the top
          # level, so the newest top-level mtime is the last use.
          let last_used = (ls --all $entry.name | sort-by modified | last | get modified)
          { base: $entry.name, workspace: $workspace, last_used: $last_used }
        }
      | compact
      | sort-by last_used
    )

    let stale = ($idle | where {|b| (not ($b.workspace | path exists)) or $b.last_used < $cutoff })
    for b in $stale {
      let reason = if ($b.workspace | path exists) {
        $"($b.workspace) unused since ($b.last_used | format date '%Y-%m-%d %H:%M')"
      } else {
        $"workspace ($b.workspace) is gone"
      }
      prune-base $b.base $reason $dry_run
    }

    let stale_bases = ($stale | get base)
    let rest = ($idle | where {|b| $b.base not-in $stale_bases })
    mut pruned = ($stale | length)
    for b in $rest {
      let used = (used-percent $root)
      if $used <= $max_used_percent { break }
      let reason = $"disk ($used)% used, ($b.workspace) unused since ($b.last_used | format date '%Y-%m-%d %H:%M')"
      # A dry run frees nothing, so it lists every idle base in deletion order.
      prune-base $b.base $reason $dry_run
      $pruned += 1
    }

    if $pruned == 0 {
      print "No stale Bazel output bases."
    }
  }
''
