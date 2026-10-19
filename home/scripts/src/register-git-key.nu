#!/usr/bin/env nu

# Add this machine's git key (created on Home Manager activation) to GitHub
# as both an authentication and a signing key. Safe to re-run.

def main [] {
  let pub_path = ($env.HOME | path join ".ssh" "id_ed25519_git.pub")
  if not ($pub_path | path exists) {
    print -e $"Missing ($pub_path); activate Home Manager first."
    exit 1
  }

  # GitHub stores keys without the trailing comment
  let key = (
    open --raw $pub_path | str trim | split row " " | first 2 | str join " "
  )
  let title = $"(sys host | get hostname) git"

  # The default gh login can manage neither authentication nor signing keys
  let scopes = (
    ^gh api --include user
    | lines
    | where ($it | str starts-with --ignore-case "x-oauth-scopes:")
    | get 0?
    | default ""
    | str replace --regex "(?i)^x-oauth-scopes:" ""
    | split row ","
    | each { str trim }
  )
  let missing = (
    [admin:public_key admin:ssh_signing_key] | where $it not-in $scopes
  )
  if ($missing | is-not-empty) {
    ^gh auth refresh --hostname github.com --scopes ($missing | str join ",")
  }

  let endpoints = {authentication: "user/keys" signing: "user/ssh_signing_keys"}
  for type in [authentication signing] {
    let existing = (
      ^gh api --paginate ($endpoints | get $type) --jq ".[].key" | lines
    )
    if $key in $existing {
      print $"($type) key already on GitHub"
    } else {
      ^gh ssh-key add $pub_path --type $type --title $title
    }
  }
}
