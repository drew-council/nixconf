{ inputs, ... }:
{
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      vcs = import ./_vcs-settings.nix { inherit config pkgs; };

      # global pre-commit hook: prefer a repo's scripts/pre-commit.sh (work
      # repos), then its .githooks/pre-commit, otherwise do nothing
      preCommitHook = pkgs.writeShellApplication {
        name = "pre-commit";
        text = ''
          # resolve against the current worktree, not the main checkout
          root=$(git rev-parse --show-toplevel)

          work_hook="$root/scripts/pre-commit.sh"
          personal_hook="$root/.githooks/pre-commit"

          if [ -f "$work_hook" ]; then
            exec sh "$work_hook" "$@"
          fi

          if [ -x "$personal_hook" ]; then
            exec "$personal_hook" "$@"
          fi
        '';
      };

      weavePackage = inputs.weave.packages.${pkgs.stdenv.hostPlatform.system}.default;
      weaveExtensions = [
        "ts"
        "tsx"
        "js"
        "mjs"
        "cjs"
        "jsx"
        "py"
        "go"
        "rs"
        "java"
        "c"
        "h"
        "cpp"
        "cc"
        "cxx"
        "hpp"
        "hh"
        "hxx"
        "rb"
        "cs"
        "php"
        "swift"
        "ex"
        "exs"
        "sh"
        "f90"
        "f95"
        "f03"
        "f08"
        "xml"
        "plist"
        "svg"
        "csproj"
        "fsproj"
        "vbproj"
        "json"
        "yaml"
        "yml"
        "toml"
        "md"
        "scala"
        "sc"
        "sbt"
        "kojo"
        "mill"
        "dart"
      ];
      weaveAttributes = map (extension: "*.${extension} merge=weave") weaveExtensions;
    in
    {
      home.packages = [ weavePackage ];

      home.activation.createGitMachineKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "${vcs.machineKey}" ]; then
          run mkdir -p -m 700 "${dirOf vcs.machineKey}"
          run ${lib.getExe' pkgs.openssh "ssh-keygen"} -q -t ed25519 -N "" \
            -C "${config.my.user.name}@$(uname -n) git" -f "${vcs.machineKey}"
        fi
      '';

      # delta for git diff viewer
      programs.delta = {
        enable = true;
        options = {
          side-by-side = false;
        };
        enableGitIntegration = true;
      };

      # git configuration
      programs.git =
        let
          mkIdentityConfig = identity: {
            user = {
              inherit (identity) name email;
              signingkey = vcs.machineKey;
            };
            # bypass the 1Password agent set for Host * in ~/.ssh/config
            core.sshCommand = "ssh -i ${vcs.machineKey} -o IdentitiesOnly=yes -o IdentityAgent=none";
          };
          personalConfig = mkIdentityConfig vcs.identities.personal;
        in
        {
          enable = true;
          attributes = weaveAttributes;
          lfs.enable = true;
          # signer defaults to nixpkgs' ssh-keygen
          signing.format = "ssh";
          # recursive so personalConfig.core doesn't replace core below
          settings = lib.recursiveUpdate {
            # preferences
            init.defaultBranch = "main";
            push.autoSetupRemote = true;
            merge.weave = {
              name = "Entity-level semantic merge";
              driver = "weave-driver %O %A %B %L %P";
            };
            hook.repo-pre-commit = {
              event = "pre-commit";
              command = lib.getExe preCommitHook;
            };
            core.editor = "nvim";

            # speed up large Git LFS uploads/downloads
            lfs = {
              # Default is 8; a modest increase tends to better saturate fast links.
              concurrenttransfers = 16;
              # Avoid restarting large transfers during brief idle/stall periods.
              activitytimeout = 60;
              # Use resumable uploads when the LFS server advertises tus.io support.
              tustransfers = true;
              transfer = {
                # Default is 100; fewer Batch API round trips for many LFS objects.
                batchSize = 256;
              };
            };

            # ssh commit signing with the machine key
            commit.gpgsign = true;
          } personalConfig; # set default to personal
        };
    };
}
