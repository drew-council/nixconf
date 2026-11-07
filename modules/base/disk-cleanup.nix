# Nix generation GC and Go cache cleanup.
{
  flake.modules = {
    homeManager.base =
      { lib, pkgs, ... }:
      {
        # Old user generations pin every store path they reference; 7,000+ dead
        # paths had piled up before this. Only the user's profiles are covered;
        # system generations on macOS are handled by the root daemon below.
        nix.gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };
        # On darwin the module appends `options` as a single argv element, so
        # nix saw one unknown flag '--delete-older-than 14d' and the job failed
        # every week. Split the arguments ourselves; Determinate's nix matches
        # the daemon.
        launchd.agents.nix-gc.config.ProgramArguments = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
          lib.mkForce [
            "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
            "--delete-older-than"
            "14d"
          ]
        );

        # Go never caps GOCACHE (only entries unused for 5 days are trimmed) and
        # never trims GOMODCACHE, so with a dozen worktrees running go test,
        # gopls and Bazel (GO_REPOSITORY_USE_HOST_CACHE) they once reached
        # ~25 GiB and ~12 GiB. Both refill on demand.
        launchd.agents.go-clean = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          enable = true;
          config = {
            ProgramArguments = [
              (lib.getExe pkgs.go)
              "clean"
              "-cache"
              "-modcache"
            ];
            StartCalendarInterval = [
              {
                Weekday = 0;
                Hour = 12;
                Minute = 0;
              }
            ];
          };
        };
      };

    # With nix.enable off, nix-darwin's nix.gc is unavailable, and
    # Determinate's own GC never deletes generations, so every darwin-system
    # generation (72 before this) stayed a GC root. Home Manager's nix.gc
    # only reaches the user's profiles; this root job prunes
    # /nix/var/nix/profiles.
    darwin.base.launchd.daemons.nix-gc.serviceConfig = {
      ProgramArguments = [
        "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
        "--delete-older-than"
        "14d"
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 12;
          Minute = 0;
        }
      ];
    };
  };
}
