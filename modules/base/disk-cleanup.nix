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

        # Agent worktrees grew GOCACHE from 24 to 54 GiB in two days, faster
        # than Go's 5-day trim. Go refreshes an entry's mtime on use once it is
        # an hour old, so mtime is the last use; drop entries unused for a day.
        # The top level holds README and trim.txt, which Go expects to find.
        systemd.user.services.go-cache-trim = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          Unit.Description = "Delete Go build cache entries unused for a day";
          Service = {
            Type = "oneshot";
            ExecStart = toString (
              pkgs.writeShellScript "go-cache-trim" ''
                cache=$(${lib.getExe pkgs.go} env GOCACHE)
                [ -d "$cache" ] || exit 0
                ${pkgs.findutils}/bin/find "$cache" -mindepth 2 -type f -mmin +1440 -delete
              ''
            );
          };
        };
        systemd.user.timers.go-cache-trim = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          Unit.Description = "Daily Go build cache trim";
          Timer = {
            OnCalendar = "daily";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
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
