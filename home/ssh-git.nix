{
  inputs,
  pkgs,
  vars,
  ...
}:
let
  genKeyFile =
    name: value:
    pkgs.writeTextFile {
      name = "${name}.pub";
      text = value;
    };

  vcs = import ./vcs-settings.nix { inherit pkgs vars; };
  publicKeys = {
    personalGitHub = vcs.identities.personal.sshPublicKey;
    hetzner = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGogIJ4uaReEMnM8eRedZh0OVq/4AAs4H8xdiWjvf6YF";
  };
  publicKeyFiles = builtins.mapAttrs genKeyFile publicKeys;

  onePassPath = vcs.onePassword.agentSocket;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
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

  # -------SSH CONFIGURATION-------
  # home manager version adds several extra options i do not want
  home.file.".ssh/config".text = ''
    Host hetzner
        HostName 178.156.186.220
        Port 52681
        User drew
        IdentityFile ${publicKeyFiles.hetzner}
        IdentityAgent "${onePassPath}"

    Host igneous
        HostName 192.168.1.123
        User drew
        IdentityFile ${publicKeyFiles.hetzner}
        IdentitiesOnly yes
        IdentityAgent "${onePassPath}"

    Host *
        IdentityAgent "${onePassPath}"
  '';

  # You can test the available keys and their order of attempt by running:
  #  SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l
  xdg.configFile."1Password/ssh/agent.toml".source =
    (pkgs.formats.toml { }).generate "1Password-ssh-agent.toml"
      {
        "ssh-keys" = map (item: { inherit item; }) [
          "tf64ipw7poybpzazfzz3geyefu" # personal github
          "av5h4r2kyfwueck7e7jq7gw5cu" # hetzner
        ];
      };

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
      mkIdentityConfig = identity: publicKeyFile: {
        user = {
          inherit (identity) name email;
          signingkey = identity.sshPublicKey;
        };
        core.sshCommand = "ssh -i ${publicKeyFile}";
      };
      personalConfig = mkIdentityConfig vcs.identities.personal publicKeyFiles.personalGitHub;
    in
    {
      enable = true;
      attributes = weaveAttributes;
      lfs.enable = true;
      signing = {
        format = "ssh";
        # should be declared deterministically, but can't get same pkg as in nixos config
        signer = vcs.onePassword.sshSigner;
      };
      settings = {
        # preferences
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        merge.weave = {
          name = "Entity-level semantic merge";
          driver = "weave-driver %O %A %B %L %P";
        };
        core.hooksPath = ".githooks";
        core.editor = vars.defaults.termEditor;

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

        # 1password ssh commit signing (disabled on macOS)
        commit.gpgsign = !isDarwin;
      }
      // personalConfig; # set default to personal
    };
}
