{
  flake.modules.nixos = {
    terminal.programs._1password.enable = true;

    desktop-linux =
      { config, ... }:
      {
        programs._1password-gui = {
          enable = true;
          # Certain features, including CLI integration and system authentication support,
          # require enabling PolKit integration on some desktop environments (e.g. Plasma).
          polkitPolicyOwners = [ config.my.user.name ];
        };

        # set 1password to trust zen and helium to integrate with browser extension
        environment.etc = {
          "1password/custom_allowed_browsers" = {
            text = ''
              zen
              .zen-wrapped
              helium
              helium-wrapper
            '';
            mode = "0755";
          };
        };
      };
  };
}
