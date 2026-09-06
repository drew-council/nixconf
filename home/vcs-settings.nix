{ pkgs, vars }:
{
  identities = {
    personal = {
      name = "drew-council";
      email = "andrew.p.council@gmail.com";
      sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOjbUnES0AUVvsqNzMdCix3Qp+XRpKiS7tm6PR6u7WTY";
    };
  };

  onePassword =
    if pkgs.stdenv.hostPlatform.isDarwin then
      {
        agentSocket = "${vars.home}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
        sshSigner = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      }
    else
      {
        agentSocket = "${vars.home}/.1password/agent.sock";
        sshSigner = "/run/current-system/sw/bin/op-ssh-sign";
      };
}
