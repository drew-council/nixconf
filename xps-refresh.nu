#!/usr/bin/env nu

# Temporary recovery script. Run from the same checkout used for the cache warm-up:
#   nu xps-refresh.nu
# Builds the flake and sets the next boot generation; never switches or reboots.
# Uses root-scoped cache options rather than editing /etc/nix/nix.conf or relying
# on the old daemon trusting the invoking user. No Cachix upload token is needed.

const warmed_system = "/nix/store/73m4hpc2wppbi1xmzssw0xxsw7hg6w6g-nixos-system-xps-26.11.20261008.e7439b6"
const cached_nh = "/nix/store/686hw7j34n30mxyha31xdqx3nss8dzbq-nh-4.4.2"
const cached_nix = "/nix/store/cv7vd1i121mj84jb694gjc3xvr0da4xw-nix-2.34.8"

def run-root [args: list<string>] {
  ^sudo ...$args
  if $env.LAST_EXIT_CODE != 0 {
    error make {msg: $"Command failed; stopping: ($args | str join ' ')"}
  }
}

def main [
  --dry-run # Show the plan without downloading, building, or changing boot entries
] {
  let repo = $env.FILE_PWD
  let config = (open ($repo | path join "substituters_config.json"))
  let cache_options = [
    "--option"
    "experimental-features"
    "nix-command flakes"
    "--option"
    "extra-substituters"
    ($config | get extra-substituters | str join " ")
    "--option"
    "extra-trusted-public-keys"
    ($config | get extra-trusted-public-keys | str join " ")
    # Discard previous cache misses now that the closure has been uploaded.
    "--option"
    "narinfo-cache-negative-ttl"
    "0"
    "--option"
    "substitute"
    "true"
  ]
  let eval_args = (
    [
      $"($cached_nix)/bin/nix"
      "eval"
      "--raw"
      "--no-update-lock-file"
      $"($repo)#nixosConfigurations.xps.config.system.build.toplevel.outPath"
    ] | append $cache_options
  )
  let bootstrap_args = (
    [
      "nix"
      "build"
      $cached_nix
      $cached_nh
      "--no-link"
      "--max-jobs"
      "0"
    ] | append $cache_options
  )
  # Bootstrap without evaluating any flake: the old Nix cannot read modern
  # relative-path lock entries. Use the downloaded client for eval and nh's
  # subprocesses; leave the running daemon and system configuration unchanged.
  # Use plain nh rather than the Cachix upload wrapper (no token required).
  let boot_args = (
    [
      "env"
      $"PATH=($cached_nix)/bin:($env.PATH | str join ':')"
      $"($cached_nh)/bin/nh"
      "os"
      "boot"
      "--hostname"
      "xps"
      "--bypass-root-check"
      "--elevation-strategy"
      "none"
      "--no-update-lock-file"
      $repo
      "--"
    ] | append $cache_options
  )

  if $dry_run {
    print "Download cached Nix and nh without flake evaluation, check the warmed XPS system, then rebuild and set the boot default:"
    for args in [$bootstrap_args $eval_args $boot_args] {
      print ($args | prepend "sudo" | to nuon)
    }
    return
  }

  if ((^hostname | str trim) != "xps") {
    error make {msg: "Run this script on xps only; it changes the local boot generation."}
  }
  if ($nu.os-info.name != "linux") {
    error make {msg: "This script requires NixOS."}
  }

  print "Downloading current Nix and nh from the configured caches (no compilation)..."
  run-root $bootstrap_args

  print "Checking the flake against the system warmed on igneous..."
  let evaluation = (^sudo ...$eval_args | complete)
  if $evaluation.exit_code != 0 {
    error make {msg: $"Flake evaluation failed; stopping: ($evaluation.stderr)"}
  }
  let actual = ($evaluation.stdout | str trim)
  if $actual != $warmed_system {
    error make {msg: $"This checkout produces ($actual), not the cached system ($warmed_system). Use the warmed checkout or warm the new system first."}
  }

  print "Building XPS with caches enabled, then setting the next boot generation..."
  run-root $boot_args
  print "Done. The running system is unchanged. Reboot when ready; the previous generation remains available in the boot menu."
}
