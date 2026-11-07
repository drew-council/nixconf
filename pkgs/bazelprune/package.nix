# Bazel writes the workspace path into DO_NOT_BUILD_HERE in every output base,
# and each worktree gets its own output base, so deleting a worktree strands an output base of several GiB. Nothing else ever
# reclaims them: 20 stranded bases once filled ~150 GiB. Bazel never shrinks a
# live worktree's base either: one that has run the Go tests holds ~25 GiB of
# go_test binaries (one per _test.go file) indefinitely. This walks the
# output_user_root and removes bases whose workspace is gone or that no command
# has used in --max-idle-days. Bazel 9 clones disk-cache hits into the output
# base, so rebuilding a pruned worktree costs APFS clones rather than a full
# build while the disk cache still holds them.
{
  lib,
  nushell,
  writeScriptBin,
  # Must match --output_user_root in the .bazelrc.
  outputUserRoot ? "/var/tmp/_bazel",
}:
writeScriptBin "bazelprune" ''
  #!${lib.getExe nushell}

  # Delete Bazel output bases whose workspace directory no longer exists, or
  # that have not been used in --max-idle-days.
  def main [--dry-run, --max-idle-days: int = 3] {
    let root = "${outputUserRoot}"
    if not ($root | path exists) {
      return
    }
    let cutoff = ((date now) - ($max_idle_days * 1day))

    let stale = (
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
          if not ($workspace | path exists) {
            return { base: $entry.name, reason: $"workspace ($workspace) is gone" }
          }
          # Every command writes a profile and takes the lock at the top
          # level, so the newest top-level mtime is the last use.
          let last_used = (ls --all $entry.name | sort-by modified | last | get modified)
          if $last_used < $cutoff {
            return { base: $entry.name, reason: $"($workspace) unused since ($last_used | format date '%Y-%m-%d')" }
          }
          null
        }
      | compact
    )

    if ($stale | is-empty) {
      print "No stale Bazel output bases."
      return
    }

    for base in $stale {
      print $"($base.base): ($base.reason)"
      if not $dry_run {
        # Bazel marks parts of the output tree read-only.
        ^chmod -R u+w $base.base
        rm --recursive --force --permanent $base.base
      }
    }
  }
''
