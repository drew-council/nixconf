#!/usr/bin/env nix-shell
#! nix-shell -i nu -p nushell gh git git-lfs bat nixfmt

use std/assert

def conf-dir [] {
  let script_dir = ($env.FILE_PWD? | default "")
  if ($script_dir | path join "flake.nix" | path exists) {
    $script_dir
  } else {
    $nu.home-dir | path join "nixconf"
  }
}

def say [msg: string] {
  print $"(ansi cyan_bold)($msg)(ansi reset)"
}

def is-darwin [] {
  $nu.os-info.name == "macos"
}

def substituter-options [] {
  let config = (open ((conf-dir) | path join "substituters_config.json"))
  [
    "--option"
    "extra-substituters"
    ($config | get "extra-substituters" | str join " ")
    "--option"
    "extra-trusted-public-keys"
    ($config | get "extra-trusted-public-keys" | str join " ")
  ]
}

# nix-darwin has no boot generation, so darwin always switches
def rebuild [hostname: string] {
  say $"rebuilding for ($hostname)"
  let options = (substituter-options)

  if (is-darwin) {
    if (which darwin-rebuild | is-not-empty) {
      sudo darwin-rebuild switch --flake $".#($hostname)" ...$options
    } else {
      say "darwin-rebuild not found, bootstrapping via nix run"
      (
        nix run nix-darwin -- switch --flake $".#($hostname)"
        ...$options
      )
    }
  } else {
    nixos-rebuild boot --sudo --flake $".#($hostname)" ...$options
  }
}

def current-hostname [] {
  if (is-darwin) { "macos" } else { (hostname) }
}

def "main rebuild" [] {
  cd (conf-dir)
  rebuild (current-hostname)
}

def "main install" [] {
  let darwin = (is-darwin)
  let hostname = if $darwin {
    say "darwin detected, using the fixed `macos` configuration"
    "macos"
  } else {
    (input "new system's hostname: ")
  }

  cd ~
  $env.NIX_CONFIG = "experimental-features = nix-command flakes"

  let git_user = {
    "user.email": "andrew.p.council@gmail.com"
    "user.name": "drew-council"
  }

  # set git user conf settings (temp, will come from home manager later)
  $git_user | items {|key val|
    git config --global $key $val
  }

  # clone with https (will switch to proper ssh later)
  let conf = $env.HOME | path join "nixconf"
  if ($conf | path exists | not $in) {
    git clone https://github.com/drew-council/nixconf.git
  }
  cd $conf

  let host_dir = ($conf | path join "hosts" $hostname)
  assert ($host_dir | path exists) $"host config directory not found: ($host_dir)"

  if $darwin {
    say "skipping hardware configuration and host registration (not used on darwin)"
  } else {
    let hardware_config = ($host_dir | path join "hardware-configuration.nix")
    assert ("/etc/nixos/hardware-configuration.nix" | path exists) "/etc/nixos/hardware-configuration.nix not found"
    say $"copying hardware configuration to ($hardware_config)"
    cp --force /etc/nixos/hardware-configuration.nix $hardware_config

    # add hostname to the generated configurations
    let config_file = ($conf | path join "build_config.json")
    let old_config = (open $config_file)
    let existing_hosts = ($old_config | get hosts)
    let updated_hosts = if ($existing_hosts | any {|host| $host == $hostname }) {
      $existing_hosts
    } else {
      $existing_hosts | append $hostname
    }
    (
      $old_config
      | update hosts $updated_hosts
      | save --force $config_file
    )

    # start new branch for this host temporarily
    git checkout -b $hostname
    git add -A
    git commit -m $"adding host ($hostname)"
  }

  rebuild $hostname

  # unset temp git config settings
  $git_user | items {|key val|
    git config --global --unset $key
  }

  if $darwin {
    say "finished setup, open a new shell and set up git properly for ~/nixconf"
  } else {
    say "finished setup, reboot and set up git properly for ~/nixconf"
  }
}

def clone-if-missing [dest: path url: string] {
  if ($dest | path exists) {
    say $"($dest) already exists, skipping clone"
  } else {
    git clone $url $dest
  }
}

def "main configure" [] {
  say "configuration stage"
  input "make sure 1password is fully configured."

  say "switching nixconf to use ssh"
  cd ~/nixconf
  git remote set-url origin git@github.com:drew-council/nixconf.git

  def read [ref: string] {
    ^op --account L23KMYOBNVHLPGSIPDX7BAQ5LA read $ref
  }

  say "setting up atuin"
  try {
    let username = (read "op://Private/atuin sync/username")
    let password = (read "op://Private/atuin sync/password")
    let key = (read "op://Private/atuin sync/key")
    atuin login --username $username --password $password --key $key
    atuin sync
  } catch {|err|
    say $"atuin setup skipped: ($err.msg)"
  }

  say "setting up cachix"
  try {
    read "op://Private/cachix-personal/credential" | cachix authtoken --stdin
  } catch {|err|
    say $"cachix setup skipped: ($err.msg)"
  }

  say "setting up zed"
  clone-if-missing ($nu.home-dir | path join ".config" "zed") "git@github.com:drew-council/zed.git"

  say "setting up codex"
  clone-if-missing ($nu.home-dir | path join ".codex") "git@github.com:drew-council/codex-config.git"
}

def main [] {
  say "choose a subcommand"
}
