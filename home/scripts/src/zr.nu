#!/usr/bin/env nu

# Build my Zed checkout (~/personal/zed) inside its direnv dev shell, then
# launch the fresh binary on the given paths.
#
# The default `dev` profile is incremental and keeps the hot crates (gpui
# macros, tree-sitter, taffy, ...) at opt-level 3, so small edits relink in
# seconds. --release builds `release-fast` with incremental compilation on and
# unpacked debuginfo (skips dsymutil) for when dev feels too sluggish.
#
# Only the build runs in the dev shell; Zed itself starts from the caller's
# directory with the caller's environment, so cargo/nix variables don't leak
# into rust-analyzer and invalidate the build cache.

def fail [msg: string] {
  error make --unspanned {msg: $msg}
}

def main [
  ...paths: path # files or directories to open
  --release (-r) # build the release-fast profile instead of dev
] {
  let zed_dir = ($env.HOME | path join personal zed)
  if not ($zed_dir | path exists) {
    fail $"($zed_dir) does not exist"
  }

  let profile = if $release { "release-fast" } else { "dev" }
  let target_subdir = if $release { "release-fast" } else { "debug" }
  let profile_env = if $release {
    {
      CARGO_PROFILE_RELEASE_FAST_INCREMENTAL: "true"
      CARGO_PROFILE_RELEASE_FAST_SPLIT_DEBUGINFO: "unpacked"
    }
  } else {
    {}
  }

  # resolve paths against the caller's cwd before leaving it
  let paths = ($paths | each {|p| $p | path expand })

  do {
    cd $zed_dir
    with-env $profile_env {
      ^direnv exec . cargo build --package zed --bin zed --profile $profile --jobs 8
    }
  }

  ^($zed_dir | path join target $target_subdir zed) ...$paths
}
