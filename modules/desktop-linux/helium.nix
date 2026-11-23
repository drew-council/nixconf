{ inputs, ... }:
{
  flake.modules.nixos.desktop-linux =
    { pkgs, ... }:
    {
      imports = [ inputs.helium-browser.nixosModules.default ];

      # Policies land in /etc/chromium/policies/managed,
      # so Chromium picks them up as well.
      # https://chromeenterprise.google/policies/
      programs.helium = {
        enable = true;
        package = inputs.helium-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;
        policies = {
          # Keys are Chrome Web Store extension IDs.
          ExtensionSettings =
            let
              # Helium omits prodversion from update checks,
              # so Google's update URL always answers noupdate.
              # Helium's Web Store proxy serves the CRX instead.
              forceInstall = {
                installation_mode = "force_installed";
                update_url = "https://services.helium.imput.net/ext";
                override_update_url = true;
              };
            in
            {
              "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = forceInstall; # 1Password
            };
          PasswordManagerEnabled = false; # 1Password handles this
          RestoreOnStartup = 1; # continue where you left off
          DefaultSearchProviderEnabled = true;
          DefaultSearchProviderName = "unduck";
          DefaultSearchProviderSearchURL = "https://unduck.link?q={searchTerms}";
        };
      };
    };
}
