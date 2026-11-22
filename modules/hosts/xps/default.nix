{
  hosts.xps = {
    system = "x86_64-linux";

    features = [
      "base"
      "home-lan"
      "terminal"
      "desktop"
      "desktop-linux"
      "t3code"
      "hermes"
    ];

    module =
      { config, ... }:
      {
        imports = [
          ./_hardware.nix
          ./_peanut-map.nix
        ];

        services.logind.settings.Login = {
          HandleLidSwitch = "ignore";
          HandleLidSwitchExternalPower = "ignore";
          HandleLidSwitchDocked = "ignore";
        };

        # Ensure logind reloads changed policy without restarting user sessions.
        systemd.services.systemd-logind.restartTriggers = [
          config.environment.etc."systemd/logind.conf".source
        ];

        # Pull-only: Hermes has full access to this machine,
        # and the cache signs whatever a token holder uploads.
        my.nixCache.push = false;

        users.users.${config.my.user.name}.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINPILydKagpHBNoXFBEcUxqf4wFZDD6GRY09FGfLt/EH"
        ];

        system.stateVersion = "25.11";
      };
  };
}
