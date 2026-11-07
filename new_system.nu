#!/usr/bin/env nix-shell
#! nix-shell -i nu -p nushell gh git git-lfs bat nixfmt

use std/assert

def say [msg: string] {
  print $"(ansi cyan_bold)($msg)(ansi reset)"
}

def is-darwin [] {
  $nu.os-info.name == "macos"
}

def substituter-options [] {
  let config = (open substituters_config.json)
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

def host-template [hostname: string] {
  let system = $"($nu.os-info.arch)-linux"
  let state_version = (nixos-version | split row "." | first 2 | str join ".")
  $"{
  hosts.($hostname) = {
    system = \"($system)\";
    features = [
      \"base\"
      \"terminal\"
      \"desktop\"
      \"desktop-linux\"
    ];
    module = {
      imports = [ ./_hardware.nix ];
      system.stateVersion = \"($state_version)\";
    };
  };
}"
}

def create-host [hostname: string] {
  let host_dir = ("modules/hosts" | path join $hostname)
  mkdir $host_dir

  let host_file = ($host_dir | path join "default.nix")
  if ($host_file | path exists) {
    say $"($host_file) already exists, keeping it"
  } else {
    host-template $hostname | save $host_file
  }

  assert ("/etc/nixos/hardware-configuration.nix" | path exists) "/etc/nixos/hardware-configuration.nix not found"
  cp --force /etc/nixos/hardware-configuration.nix ($host_dir | path join "_hardware.nix")

  # flakes only see tracked files
  git add $host_dir
}

def "main install" [hostname?: string] {
  let darwin = (is-darwin)
  if (not $darwin) and ($hostname == null) {
    error make {msg: "usage: new_system.nu install <hostname>"}
  }
  let hostname = if $darwin {
    say "darwin detected, using the fixed `macos` configuration"
    "macos"
  } else {
    $hostname
  }

  $env.NIX_CONFIG = "experimental-features = nix-command flakes"

  # clone with https (`configure` switches to ssh later)
  let conf = ($nu.home-dir | path join "nixconf")
  if not ($conf | path exists) {
    git clone https://github.com/drew-council/nixconf.git $conf
  }
  cd $conf

  if not $darwin {
    create-host $hostname
  }

  rebuild $hostname

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
  print "usage: new_system.nu install <hostname> | configure"
}
