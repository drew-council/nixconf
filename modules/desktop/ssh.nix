{
  flake.modules.homeManager.desktop =
    { config, pkgs, ... }:
    let
      inherit (import ../terminal/_vcs-settings.nix { inherit config pkgs; }) onePassword;

      publicKeyFile =
        name: text:
        pkgs.writeTextFile {
          name = "${name}.pub";
          inherit text;
        };

      xpsKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINPILydKagpHBNoXFBEcUxqf4wFZDD6GRY09FGfLt/EH";
    in
    {
      # home manager version adds several extra options i do not want
      home.file.".ssh/config".text = ''
        Host igneous
            HostName 192.168.1.123
            User drew
            IdentityFile ${publicKeyFile "igneous" config.my.user.sshPublicKey}
            IdentitiesOnly yes
            IdentityAgent "${onePassword.agentSocket}"

        Host xps
            HostName 192.168.1.145
            User drew
            IdentityFile ${publicKeyFile "xps" xpsKey}
            IdentitiesOnly yes
            IdentityAgent "${onePassword.agentSocket}"

        Host *
            IdentityAgent "${onePassword.agentSocket}"
      '';

      # You can test the available keys and their order of attempt by running:
      #  SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l
      xdg.configFile."1Password/ssh/agent.toml".source =
        (pkgs.formats.toml { }).generate "1Password-ssh-agent.toml"
          {
            "ssh-keys" = map (item: { inherit item; }) [
              "tf64ipw7poybpzazfzz3geyefu" # personal github
              "av5h4r2kyfwueck7e7jq7gw5cu" # hetzner
              "3g5n4a5cc53mljbipupfcmr2zu" # xps
            ];
          };
    };
}
