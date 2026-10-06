{
  lib,
  pkgs,
  platform,
  vars,
  ...
}:

let
  cache = "${vars.home}/.cache/bazel";
  # Time Machine skips /var/tmp, so macOS keeps the large output_base there.
  outputBaseRoot = if platform.isDarwin then "/private/var/tmp" else "/var/tmp";
  # bazelisk 1.29.0 ships a stray bin/sha256sum (a Go test helper) that
  # collides with uutils-coreutils in the Home Manager buildEnv. Drop it.
  bazelisk = pkgs.bazelisk.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -f $out/bin/sha256sum
    '';
  });

  # Bazel writes the workspace path into DO_NOT_BUILD_HERE in every output
  # base, and each worktree gets its own output base (see .bazelrc below), so
  # deleting a worktree strands an output base of several GiB. Nothing else
  # ever reclaims them: 20 stranded bases once filled ~150 GiB. Bazel never
  # shrinks a live worktree's base either: one that has run the Go tests holds
  # ~25 GiB of go_test binaries (one per _test.go file) indefinitely. This
  # walks the output_user_root and removes bases whose workspace is gone or
  # that no command has used in --max-idle-days. Bazel 9 clones disk-cache
  # hits into the output base, so rebuilding a pruned worktree costs APFS
  # clones rather than a full build while the disk cache still holds them.
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
  bazelpruneLogDir = "${vars.home}/Library/Logs/bazelprune";

  # PATH handed to Bazel actions on NixOS. The repo sets
  # --incompatible_strict_action_env, so actions otherwise get
  # /bin:/usr/bin:/usr/local/bin, which on NixOS holds only sh and env. Bazel
  # also forwards --action_env to repository rules, so the cc toolchain
  # autodetection needs to find gcc and binutils here too. Keep the list small:
  # the PATH string is part of every action's cache key.
  bazelActionPath = lib.makeBinPath (
    with pkgs;
    [
      bash
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      diffutils
      gnutar
      gzip
      which
      file
      git
      python3
      gcc
      binutils
    ]
  );
in
{
  # Tools from the sheer repo's Brewfile / scripts/setup.sh that are not
  # already installed globally (buf, go, gopls, nodejs 24, and docker-buildx
  # come from home/packages/terminal.nix).
  home.packages =
    with pkgs;
    [
      # Note: `bazelisk` here refers to the sha256sum-free override in `let`.
      # Use bazelisk (as the repo's Brewfile does) so the exact upstream release
      # pinned in .bazelversion runs. nixpkgs bazel_8 is not a drop-in: it embeds
      # the label "8.7.0- (@non-git)" instead of "8.7.0", which lands in
      # @bazel_features_version//:version.bzl and changes the transitive .bzl
      # digest of every module extension loading bazel_features, so the committed
      # MODULE.bazel.lock reads as stale under --lockfile_mode=error. On Linux
      # the downloaded binary runs via programs.nix-ld (modules/base.nix).
      bazelisk
      # Homebrew symlinks bazel -> bazelisk; the nixpkgs package only ships
      # a bazelisk binary, so provide the bazel name ourselves.
      (writeShellScriptBin "bazel" ''exec ${lib.getExe bazelisk} "$@"'')
      delve
      firebase-tools
      gnumake # everything is driven through the repo Makefile
      google-cloud-sdk
      opentofu
      pnpm_10 # repo pins packageManager pnpm@10.x
      pulumi
      bazelprune # also runs daily, see launchd.agents / systemd.user.timers
    ]
    ++ lib.optionals platform.isLinux [
      # C compiler for cgo outside Bazel (e.g. golangci-lint via `go tool`). On
      # macOS the Xcode CLT clang fills this role; a nixpkgs gcc would shadow
      # it on PATH. Inside Bazel the compiler comes from bazelActionPath.
      pkgs.gcc
      # `bazel run` of py_binary targets (e.g. //:format's multirun) execs the
      # rules_python stub with the client PATH; its `#!/usr/bin/env python3`
      # needs any python3 there before it re-execs the hermetic interpreter.
      pkgs.python3
    ];

  # Daily run of bazelprune. Worktrees come and go daily, so without this the
  # stranded and idle output bases quietly eat the disk. launchd runs a missed
  # interval on wake.
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

  # Bazel does not expand ~ or $HOME in .bazelrc, so every path is absolute.
  home.file.".bazelrc".text = ''
    # One output_base per worktree (hashed from the workspace path) under
    # outputBaseRoot, so every worktree keeps its own long-lived server. A Bazel
    # server is bound to a single workspace, so a shared output_base would make
    # worktrees kill each other's server. Cross-worktree reuse comes from the
    # content-addressed caches below instead.
    startup --output_user_root=${outputBaseRoot}/_bazel_${vars.user}

    common --repository_cache=${cache}/repo-cache
    common --experimental_repository_cache_hardlinks
    common --repo_contents_cache=${cache}/repo-contents-cache

    build --disk_cache=${cache}/disk-cache
    test  --disk_cache=${cache}/disk-cache
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
    # gazelle's go_repository_cache is not a reproducible repo, so it lives in
    # every output base as its own ~2 GB Go module cache. Point it at the host
    # GOMODCACHE and GOCACHE instead; MODULE.bazel.lock does not record it.
    common --repo_env=GO_REPOSITORY_USE_HOST_CACHE=1
  ''
  # NixOS lacks the FHS layout the repo's toolchains assume. Together with
  # modules/fhs-shebangs.nix (which provides /bin/bash and /usr/bin/python3
  # for actions that run with no PATH at all) this is what makes `make
  # format`, `make generate`, `bazel run` and `bazel test` work on Linux.
  + lib.optionalString platform.isLinux ''

    # `bazel run` execs --shell_executable (default /bin/bash) to launch the
    # target: "FATAL: execv of '/bin/bash' failed".
    build --shell_executable=${lib.getExe pkgs.bash}
    # Target and exec ("[for tool]") configurations each need the PATH.
    build --action_env=PATH=${bazelActionPath}
    build --host_action_env=PATH=${bazelActionPath}
    # MODULE.bazel registers toolchains_llvm, whose prebuilt clang has no
    # sysroot and so cannot find libc headers (stdio.h) on NixOS. Prefer
    # Bazel's autodetected local toolchain, i.e. the gcc from bazelActionPath.
    # --extra_toolchains wins over register_toolchains. The label is the
    # canonical bzlmod name of rules_cc's cc_configure extension repo; it is
    # not visible under an apparent name from the main module.
    build --extra_toolchains=@@rules_cc++cc_configure_extension+local_config_cc_toolchains//:all
    # protobuf's protoc version check runs `bash -c` with an empty environment,
    # and Nix's bash has no usable default PATH, so its grep and cat are not
    # found and every build that touches a proto fails with "protoc version
    # does not match". This skips only that check; the prebuilt protoc is
    # still the pinned one.
    common --@com_google_protobuf//bazel/toolchains:allow_nonstandard_protoc
  '';
}
