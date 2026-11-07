#!/usr/bin/env nu

let dir = (pwd)

let is_git_dir = ($dir | path join ".git" | path exists)
if (not $is_git_dir) {
  print "not a git directory"
  exit 1
}

(
  # problematic environment variables should be hidden
  ["LD_LIBRARY_PATH"] | each {|env_var|
    if ($env_var in $env) { hide-env $env_var }
  }
)

lazygit -p $dir
