{
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
        # Avoid a 1Password prompt after every history rewrite.
        # Signing is disabled entirely on macOS.
        sign-on-push = !pkgs.stdenv.hostPlatform.isDarwin;
      };

      signing = {
        backend = "ssh";
        behavior = "drop";
        key = personal.sshPublicKey;
        backends.ssh.program = vcs.onePassword.sshSigner;
      };
    };
  };

  # Use delta for jj's pager and Git-format diffs.
  programs.delta.enableJujutsuIntegration = true;

  # jjui is the closest feature-rich Jujutsu equivalent to Lazygit.
  home.packages = [ pkgs.jjui ];
}
