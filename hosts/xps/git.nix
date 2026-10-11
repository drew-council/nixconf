{
  lib,
  pkgs,
  vars,
  ...
}:
let
  keyFile = "${vars.home}/.ssh/hermes-github-ed25519";
in
{
  home-manager.users.${vars.user} = {
    # OpenSSH uses the first value; precede the shared Host * block.
    home.file.".ssh/config".text = lib.mkBefore ''
      Host github.com ssh.github.com
          User git
          IdentityFile ${keyFile}
          IdentityAgent none
          IdentitiesOnly yes
          BatchMode yes
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          StrictHostKeyChecking yes
    '';

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
