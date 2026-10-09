#!/usr/bin/env nu

# Temporary recovery script. Run from the same checkout used for the cache warm-up:
#   nu xps-refresh.nu
# Builds the flake and sets the next boot generation; never switches or reboots.
# Uses root-scoped cache options rather than editing /etc/nix/nix.conf or relying
# on the old daemon trusting the invoking user. No Cachix upload token is needed.

const warmed_system = "/nix/store/73m4hpc2wppbi1xmzssw0xxsw7hg6w6g-nixos-system-xps-26.11.20261008.e7439b6"
const cached_nh = "/nix/store/686hw7j34n30mxyha31xdqx3nss8dzbq-nh-4.4.2"

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
      "nix"
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
      $cached_nh
      "--no-link"
      "--max-jobs"
      "0"
    ] | append $cache_options
  )
  # Use the current, plain nh rather than an old installed nh or the Cachix
  # upload wrapper. Root can supply cache keys even on an outdated daemon.
  let boot_args = (
    [
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
    print "Check that this checkout evaluates to the warmed XPS system, download cached nh, then rebuild and set the boot default:"
    for args in [$eval_args $bootstrap_args $boot_args] {
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

  print "Checking the flake against the system warmed on igneous..."
  let evaluation = (^sudo ...$eval_args | complete)
  if $evaluation.exit_code != 0 {
    error make {msg: $"Flake evaluation failed; stopping: ($evaluation.stderr)"}
  }
  let actual = ($evaluation.stdout | str trim)
  if $actual != $warmed_system {
    error make {msg: $"This checkout produces ($actual), not the cached system ($warmed_system). Use the warmed checkout or warm the new system first."}
  }

  print "Downloading current nh from the configured caches (no compilation)..."
  run-root $bootstrap_args
  print "Building XPS with caches enabled, then setting the next boot generation..."
  run-root $boot_args
  print "Done. The running system is unchanged. Reboot when ready; the previous generation remains available in the boot menu."
}
