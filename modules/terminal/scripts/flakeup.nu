#!/usr/bin/env nu

def main [--no-push] {
  let flake = "./flake.nix"

  if (($flake | path type) != "file") {
    print $"(ansi red)no flake.nix file found(ansi reset)"
    exit 1
  }

  nix flake update
  git add flake.lock
  git commit -m "update flake.lock"

  if (not $no_push) {
    git push
  }
}
