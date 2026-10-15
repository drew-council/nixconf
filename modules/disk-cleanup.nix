# Everything that keeps the disk from filling up: Nix generation GC, Go cache
# cleanup, and pruning of Bazel output bases and caches. Imported by the
# darwin config and modules/base.nix; the per-user pieces go through Home
# Manager.
{
  lib,
  platform,
  vars,
  ...
}:

let
  # Must match --output_user_root in sheer.nix's .bazelrc.
  outputBaseRoot = if platform.isDarwin then "/private/var/tmp" else "/var/tmp";
  bazelpruneLogDir = "${vars.home}/Library/Logs/bazelprune";

  userConfig =
    { lib, pkgs, ... }:
    let
      # Bazel writes the workspace path into DO_NOT_BUILD_HERE in every output
      # base, and each worktree gets its own output base (see sheer.nix), so
      # deleting a worktree strands an output base of several GiB. Nothing
      # else ever reclaims them: 20 stranded bases once filled ~150 GiB. Bazel
      # never shrinks a live worktree's base either: one that has run the Go
      # tests holds ~25 GiB of go_test binaries (one per _test.go file)
      # indefinitely. This walks the output_user_root and removes bases whose
      # workspace is gone or that no command has used in --max-idle-days.
      # Bazel 9 clones disk-cache hits into the output base, so rebuilding a
      # pruned worktree costs APFS clones rather than a full build while the
      # disk cache still holds them.
      bazelprune = pkgs.writeScriptBin "bazelprune" ''
        #!${lib.getExe pkgs.nushell}

        # Delete Bazel output bases whose workspace directory no longer exists, or
        # that have not been used in --max-idle-days.
        def main [--dry-run, --max-idle-days: int = 3] {
          let root = "${outputBaseRoot}/_bazel_${vars.user}"
          if not ($root | path exists) {
            return
          }
          let cutoff = ((date now) - ($max_idle_days * 1day))

          let stale = (
            ls $root
            | where type == dir
            | each {|entry|
                let marker = ($entry.name | path join "DO_NOT_BUILD_HERE")
                if not ($marker | path exists) { return null }
                let workspace = (open --raw $marker | str trim)
                # Never pull an output base out from under a live server. A server
                # exits after --max_idle_secs (3h), so a live one was used recently.
                let pid_file = ($entry.name | path join "server" "server.pid.txt")
                let pid = if ($pid_file | path exists) { open --raw $pid_file | str trim } else { "" }
                if ($pid | is-not-empty) and (do { ^kill -0 $pid } | complete | get exit_code) == 0 {
                  return null
                }
                if not ($workspace | path exists) {
                  return { base: $entry.name, reason: $"workspace ($workspace) is gone" }
                }
                # Every command writes a profile and takes the lock at the top
                # level, so the newest top-level mtime is the last use.
                let last_used = (ls --all $entry.name | sort-by modified | last | get modified)
                if $last_used < $cutoff {
                  return { base: $entry.name, reason: $"($workspace) unused since ($last_used | format date '%Y-%m-%d')" }
                }
                null
              }
            | compact
          )

          if ($stale | is-empty) {
            print "No stale Bazel output bases."
            return
          }

          for base in $stale {
            print $"($base.base): ($base.reason)"
            if not $dry_run {
              # Bazel marks parts of the output tree read-only.
              ^chmod -R u+w $base.base
              rm --recursive --force --permanent $base.base
            }
          }
        }
      '';
    in
    {
      home.packages = [
        bazelprune # also runs daily, see launchd.agents / systemd.user.timers
      ];

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
      launchd.agents.nix-gc.config.ProgramArguments = lib.mkIf platform.isDarwin (
        lib.mkForce [
          "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
          "--delete-older-than"
          "14d"
        ]
      );

      # Go never caps GOCACHE (only entries unused for 5 days are trimmed) and
      # never trims GOMODCACHE, so with a dozen worktrees running go test,
      # gopls and Bazel (GO_REPOSITORY_USE_HOST_CACHE, see sheer.nix) they
      # once reached ~25 GiB and ~12 GiB. Both refill on demand.
      launchd.agents.go-clean = lib.mkIf platform.isDarwin {
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

      # Daily run of bazelprune. Worktrees come and go daily, so without this
      # the stranded and idle output bases quietly eat the disk. launchd runs
      # a missed interval on wake.
      launchd.agents.bazelprune = lib.mkIf platform.isDarwin {
        enable = true;
        config = {
          ProgramArguments = [ "${bazelprune}/bin/bazelprune" ];
          StartCalendarInterval = [
            {
              Hour = 10;
              Minute = 0;
            }
          ];
          StandardOutPath = "${bazelpruneLogDir}/stdout.log";
          StandardErrorPath = "${bazelpruneLogDir}/stderr.log";
        };
      };
      # launchd does not create parent directories for the log paths above.
      home.activation.createBazelpruneLogDir = lib.mkIf platform.isDarwin (
        lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          mkdir -p "${bazelpruneLogDir}"
        ''
      );

      systemd.user.services.bazelprune = lib.mkIf platform.isLinux {
        Unit.Description = "Remove Bazel output bases that are orphaned or idle";
        Service = {
          Type = "oneshot";
          ExecStart = "${bazelprune}/bin/bazelprune";
        };
      };
      systemd.user.timers.bazelprune = lib.mkIf platform.isLinux {
        Unit.Description = "Daily bazelprune";
        Timer = {
          OnCalendar = "daily";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };

      # Merged into the rest of the .bazelrc in sheer.nix.
      home.file.".bazelrc".text = ''
        # Garbage-collect the disk cache in the background once a server has been
        # idle for 5m: least recently used entries go until it is under the size,
        # and entries unused for the max age go regardless. Keep the max age above
        # bazelprune's --max-idle-days so a pruned worktree rebuilds from clones.
        common --experimental_disk_cache_gc_max_size=50G
        common --experimental_disk_cache_gc_max_age=7d
        # The repo contents cache keeps every version of every external repo it
        # has fetched, so a dependency bump or Bazel upgrade leaves the old ones
        # for the 14d default (the Bazel 9 upgrade left ~55 GB). A dropped repo is
        # re-extracted from the repository cache, mostly without the network.
        common --repo_contents_cache_gc_max_age=7d
      '';
    };
in
{
  config = lib.mkMerge [
    { home-manager.users.${vars.user} = userConfig; }

    # With nix.enable off, nix-darwin's nix.gc is unavailable, and
    # Determinate's own GC never deletes generations, so every darwin-system
    # generation (72 before this) stayed a GC root. Home Manager's nix.gc
    # only reaches the user's profiles; this root job prunes
    # /nix/var/nix/profiles.
    (lib.optionalAttrs platform.isDarwin {
      launchd.daemons.nix-gc.serviceConfig = {
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
    })
  ];
}
