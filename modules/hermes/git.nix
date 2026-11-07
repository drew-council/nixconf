{
  flake.modules.homeManager.hermes =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      keyFile = "${config.my.user.home}/.ssh/hermes-github-ed25519";
    in
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings."github.com ssh.github.com" = {
          User = "git";
          IdentityFile = keyFile;
          IdentityAgent = "none";
          IdentitiesOnly = true;
          BatchMode = true;
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          StrictHostKeyChecking = true;
        };
      };

      programs.git = {
        signing.signer = lib.mkForce "${pkgs.openssh}/bin/ssh-keygen";
        settings = {
          user = {
            name = lib.mkForce "Hermes Agent";
            email = lib.mkForce "45700916+drew-council@users.noreply.github.com";
            signingkey = lib.mkForce keyFile;
          };
          core.sshCommand = lib.mkForce "${pkgs.openssh}/bin/ssh";
          commit.gpgsign = lib.mkForce false;
          tag.gpgsign = lib.mkForce false;
          tag.forceSignAnnotated = lib.mkForce false;
        };
      };
    };
}
