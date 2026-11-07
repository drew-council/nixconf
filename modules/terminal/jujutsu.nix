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
      inherit (vcs.identities) personal;
      jjIdentity = identity: {
        inherit (identity) name email;
      };
    in
    {
      programs.jujutsu = {
        enable = true;
        settings = {
          user = jjIdentity personal;

          ui = {
            editor = "nvim";
            show-cryptographic-signatures = true;
          };

          # Colocation keeps repositories available to Git-based tools and IDEs.
          git = {
            colocate = true;
            # Sign when pushing rather than after every history rewrite.
            sign-on-push = true;
          };

          signing = {
            backend = "ssh";
            behavior = "drop";
            key = vcs.machineKey;
            backends.ssh.program = lib.getExe' pkgs.openssh "ssh-keygen";
          };
        };
      };

      # Use delta for jj's pager and Git-format diffs.
      programs.delta.enableJujutsuIntegration = true;

      # jjui is the closest feature-rich Jujutsu equivalent to Lazygit.
      home.packages = [ pkgs.jjui ];
    };
}
