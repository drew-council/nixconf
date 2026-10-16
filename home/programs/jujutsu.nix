{
  lib,
  pkgs,
  vars,
  ...
}:
let
  vcs = import ../vcs-settings.nix { inherit pkgs vars; };
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
        editor = vars.defaults.termEditor;
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
}
