{
  # Hardcoded FHS shebangs that NixOS does not provide by default. NixOS only
  # ships /bin/sh and /usr/bin/env, but some prebuilt or generated tooling execs
  # other fixed paths and does so with an empty environment, so neither PATH nor
  # nix-ld can help. Today this is driven by the sheer repo's Bazel setup:
  #
  # - toolchains_llvm's cc_wrapper.sh and Bazel's own `run` command exec
  #   /bin/bash directly.
  # - rules_python's default bootstrap stub starts with `#!/usr/bin/env python3`
  #   and some py_binary actions run with use_default_shell_env = False, i.e. no
  #   PATH at all, so env falls back to /bin:/usr/bin. The stub only needs any
  #   python3 to bootstrap; it re-execs the hermetic interpreter afterwards.
  flake.modules.nixos.work =
    { pkgs, ... }:
    {
      systemd.tmpfiles.settings."10-fhs-shebangs" = {
        "/bin/bash"."L+".argument = "${pkgs.bash}/bin/bash";
        "/usr/bin/python3"."L+".argument = "${pkgs.python3}/bin/python3";
      };
    };

  flake.modules.homeManager.work =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
      inherit (config.my) user;

      cache = "${user.home}/.cache/bazel";
      # Time Machine skips /var/tmp, so macOS keeps the large output_base there.
      outputBaseRoot = if isDarwin then "/private/var/tmp" else "/var/tmp";
      outputUserRoot = "${outputBaseRoot}/_bazel_${user.name}";
      bazelpruneLogDir = "${user.home}/Library/Logs/bazelprune";
      bazelprune = pkgs.bazelprune.override { inherit outputUserRoot; };

      # bazelisk 1.29.0 ships a stray bin/sha256sum (a Go test helper) that
      # collides with uutils-coreutils in the Home Manager buildEnv. Drop it.
      bazelisk = pkgs.bazelisk.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -f $out/bin/sha256sum
        '';
      });

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
      home.packages = [
        # Note: `bazelisk` here refers to the sha256sum-free override in `let`.
        # Use bazelisk (as the repo's Brewfile does) so the exact upstream release
        # pinned in .bazelversion runs. nixpkgs bazel_8 is not a drop-in: it embeds
        # the label "8.7.0- (@non-git)" instead of "8.7.0", which lands in
        # @bazel_features_version//:version.bzl and changes the transitive .bzl
        # digest of every module extension loading bazel_features, so the committed
        # MODULE.bazel.lock reads as stale under --lockfile_mode=error. On Linux
        # the downloaded binary runs via programs.nix-ld.
        bazelisk
        # Homebrew symlinks bazel -> bazelisk; the nixpkgs package only ships
        # a bazelisk binary, so provide the bazel name ourselves.
        (pkgs.writeShellScriptBin "bazel" ''exec ${lib.getExe bazelisk} "$@"'')
        bazelprune # also runs hourly, see launchd.agents / systemd.user.timers
      ];

      # Bazel does not expand ~ or $HOME in .bazelrc, so every path is absolute.
      home.file.".bazelrc".text = ''
        # One output_base per worktree (hashed from the workspace path) under
        # outputBaseRoot, so every worktree keeps its own long-lived server. A Bazel
        # server is bound to a single workspace, so a shared output_base would make
        # worktrees kill each other's server. Cross-worktree reuse comes from the
        # content-addressed caches below instead.
        startup --output_user_root=${outputUserRoot}

        common --repository_cache=${cache}/repo-cache
        common --experimental_repository_cache_hardlinks
        common --repo_contents_cache=${cache}/repo-contents-cache

        build --disk_cache=${cache}/disk-cache
        test  --disk_cache=${cache}/disk-cache
        # gazelle's go_repository_cache is not a reproducible repo, so it lives in
        # every output base as its own ~2 GB Go module cache. Point it at the host
        # GOMODCACHE and GOCACHE instead; MODULE.bazel.lock does not record it.
        common --repo_env=GO_REPOSITORY_USE_HOST_CACHE=1

        # Garbage-collect the disk cache in the background once a server has been
        # idle for 5m: least recently used entries go until it is under the size,
        # and entries unused for the max age go regardless. Keep the max age above
        # bazelprune's --max-idle-hours so a pruned worktree rebuilds from clones.
        common --experimental_disk_cache_gc_max_size=50G
        common --experimental_disk_cache_gc_max_age=7d
        # The repo contents cache keeps every version of every external repo it
        # has fetched, so a dependency bump or Bazel upgrade leaves the old ones
        # for the 14d default (the Bazel 9 upgrade left ~55 GB). A dropped repo is
        # re-extracted from the repository cache, mostly without the network.
        common --repo_contents_cache_gc_max_age=7d
      ''
      # NixOS lacks the FHS layout the repo's toolchains assume. Together with
      # the shebangs in nixos.work above (which provide /bin/bash and
      # /usr/bin/python3 for actions that run with no PATH at all) this is what
      # makes `make format`, `make generate`, `bazel run` and `bazel test` work
      # on Linux.
      + lib.optionalString isLinux ''

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

      # Hourly run of bazelprune. Agent worktrees each build a base of up to
      # tens of GiB, so a day of them can fill the disk. launchd runs a missed
      # interval on wake.
      launchd.agents.bazelprune = lib.mkIf isDarwin {
        enable = true;
        config = {
          ProgramArguments = [ "${bazelprune}/bin/bazelprune" ];
          StartInterval = 3600;
          StandardOutPath = "${bazelpruneLogDir}/stdout.log";
          StandardErrorPath = "${bazelpruneLogDir}/stderr.log";
        };
      };
      # launchd does not create parent directories for the log paths above.
      home.activation.createBazelpruneLogDir = lib.mkIf isDarwin (
        lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          mkdir -p "${bazelpruneLogDir}"
        ''
      );

      systemd.user.services.bazelprune = lib.mkIf isLinux {
        Unit.Description = "Remove Bazel output bases that are orphaned or idle";
        Service = {
          Type = "oneshot";
          # Output bases share a dedicated disk with home, so free space there
          # is the budget. Bases with a live server are never deleted.
          ExecStart = "${bazelprune}/bin/bazelprune --max-used-percent 70";
        };
      };
      systemd.user.timers.bazelprune = lib.mkIf isLinux {
        Unit.Description = "Hourly bazelprune";
        Timer = {
          OnCalendar = "hourly";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
