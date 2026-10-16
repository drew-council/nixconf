{ pkgs, vars }:
{
  identities = {
    personal = {
      name = "drew-council";
      email = "andrew.p.council@gmail.com";
    };
  };

  # passphrase-less key generated per machine on Home Manager activation, so
  # git can push and sign without 1Password (over ssh, or while it's locked);
  # add it to GitHub with `register-git-key`
  machineKey = "${vars.home}/.ssh/id_ed25519_git";

  onePassword.agentSocket =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${vars.home}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
      "${vars.home}/.1password/agent.sock";
}
