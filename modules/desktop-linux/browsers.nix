{ inputs, ... }:
{
  flake.modules.nixos.desktop-linux =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      environment.systemPackages = with pkgs; [
        inputs.zen-browser.packages.${system}.default # preferred browser
        inputs.helium-browser.packages.${system}.default # privacy-focused chromium fork
        google-chrome
        agent-browser # browser automation CLI for AI agents
      ];

      security.chromiumSuidSandbox.enable = true;
    };

  flake.modules.homeManager.desktop-linux =
    { config, ... }:
    {
      programs.chromium = {
        enable = true;
        commandLineArgs = [
          "--remote-debugging-port=9222"
        ];
      };

      programs.firefox = {
        enable = true;
        configPath = "${config.xdg.configHome}/mozilla/firefox";

        # https://nix-community.github.io/home-manager/options.html#opt-programs.firefox.profiles
        profiles = {
          default = {
            name = config.my.user.name; # name as listed in about:profiles
            id = 0;
            isDefault = true;
            settings = {
              browser.newtabpage.activity-stream = {
                feeds.section.highlights = false;
                showSponsoredTopSites = false;
              };
              browser.aboutConfig.showWarning = false;
              # restores previous session on startup
              browser.startup.page = 3;
              extensions.pocket.enabled = false;
              sidebar = {
                revamp = true;
                verticalTabs = true;
              };
            };
            search = {
              force = true;
              engines = {
                "unduck" = {
                  urls = [ { template = "https://unduck.link?q={searchTerms}"; } ];
                  icon = "https://unduck.link/favicon.ico";
                  updateInterval = 24 * 60 * 60 * 1000; # every day
                };
                bing.metaData.hidden = true;
              };
              default = "unduck";
              privateDefault = "ddg";
            };
            extensions.force = true; # needed to enable catppuccin theming
          };
        };
      };
    };
}
