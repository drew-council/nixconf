# --------- CONSTS ---------

const PROMPTS = {
  rust_lint: "
run `mask lint rust` and fix all warnings and errors.

we want to generally avoid panics. if possible, errors should be propogated up.
if impossible or if errors are truly certain to never occurr, you should use .expect() with an explicit nolint comment with an explanation comment explaining why this is safe to use
> in test files, do not panic. use `assertables` properly to assert what you need to check.

do not attempt to circumvent with inlined panic calls.
"
  git_conflicts: "
view the git context for the current repository branch and main.
then, resolve all conflicts and proceed with the current operation (rebase, cherry pick, merge, etc.) until fully complete and all conflicts are resolved.

when resolving conflicts, ALWAYS analyze semantically and preserve the intention of BOTH sides of the conflict whenever possible.
if it is unclear, you should read commit messages and understand the contextual info such that you can safely resolve without deleting crucial work.
"
}

# --------- COMMANDS ---------

# make input json and print with syntax highlighting
export def pjp [] {
  $in | to json | bat -l json
}

# Copy pipeline input to the system clipboard, or paste clipboard contents with no input.
export def clip []: [nothing -> any any -> nothing] {
  let input = $in
  let is_macos = ($nu.os-info.name == "macos")

  if ($input == null) {
    if $is_macos {
      ^pbpaste
    } else {
      ^wl-paste
    }
  } else {
    let input_type = ($input | describe)
    let clipboard_input = if (($input_type == "string") or ($input_type == "binary")) {
      $input
    } else {
      $input | to json
    }

    if $is_macos {
      $clipboard_input | ^pbcopy
    } else {
      $clipboard_input | ^wl-copy
    }
  }
}

# Copy the current directory to the system clipboard.
export def cwd [] {
  pwd | clip
}

# Copy the previous shell command to the system clipboard.
export def copy-last-command [] {
  let command = (
    history
    | get command
    | reverse
    | where {|cmd|
      let trimmed = ($cmd | str trim)
      ($trimmed != "copy-last-command") and ($trimmed != "clc")
    }
    | first
  )

  $command | clip
  print $"Copied: (ansi cyan)($command)(ansi reset)"
}

export alias clc = copy-last-command

# List AWS CLI profiles configured for this shell.
def aws-list-profiles [] {
  let result = (aws --no-cli-pager configure list-profiles | complete)
  let profiles = ($result.stdout | str trim | lines)

  if ($profiles | is-empty) {
    let config_file = ($env.AWS_CONFIG_FILE? | default $"($env.HOME)/.aws/config")
    error make {msg: $"No AWS profiles found in ($config_file), check if it exists and is properly configured."}
  }

  $profiles
}

# List all AWS CLI profiles.
alias alp = aws-list-profiles

# Set AWS profile for the current shell. Run without an argument to select one interactively.
def --env aws-switch-profile [profile?: string] {
  let available_profiles = (aws-list-profiles)
  let profile = if ($profile == null) {
    $available_profiles | input list --fuzzy "Select AWS profile"
  } else {
    $profile
  }

  if ($profile == null) {
    return
  }

  if not ($available_profiles | any {|available| $available == $profile }) {
    let available_profiles_text = ($available_profiles | str join "\n")
    error make {msg: $"Profile '($profile)' not configured in '($env.HOME)/.aws/config'.\nAvailable profiles: \n($available_profiles_text)"}
  }

  $env.AWS_DEFAULT_PROFILE = $profile
  $env.AWS_PROFILE = $profile
}

alias asp = aws-switch-profile

def safe-dir-cp [src dst] {
  use std/assert
  assert not ($dst | path exists) "output path already exists"
  print $"Copying ($src) -> ($dst)"
  mkdir $dst
  tar -C $src -cf - . | tar -C $dst -xf -
}

def safe-mv [src dst] {
  use std/assert
  assert not ($dst | path exists) "output path already exists"

  print $"Moving ($src) -> ($dst)"
  mv $src $dst
}

def fzf-list [] {
  str join "\n" | fzf
}

def df-fancy [] {
  df -h -P | detect columns --guess | where "Filesystem" != "tmpfs" | update "Size" {|| into filesize } | update "Used" {|| into filesize } | update "Avail" {|| into filesize }
}

def fopen [search: string] {
  let file = (fd $search ./ | fzf | str trim)
  if ($file | is-not-empty) {
    nvim $file
  }
}

# Compress a directory as a tarball using zst compression
def "tarzst compress" [directory: string] {
  use std/assert
  assert equal ($directory | path type) "dir" "Directiory to compress is not a directory!"
  let basename = ($directory | path basename | $in + ".tar.zst")
  tar -I zstd -cf $basename $directory
}

# Decompress a zst compressed tarball
def "tarzst decompress" [file: string] {
  use std/assert
  assert equal ($file | path type) "file" "Path to decompress is not a file!"
  assert ($file | str ends-with ".tar.zst") "File is not a zst compressed tarball!"
  tar -I zstd -xf $file
}
