{
  flake.modules.homeManager.desktop-linux =
    { lib, ... }:
    {
      programs.vesktop = {
        enable = true;
        # Ad-block custom CSS, should hopefully stay up-to-date with discord ads...
        vencord.extraQuickCss = lib.mkAfter ''
          @import url(https://codeberg.org/ridge/Discord-Adblock/raw/branch/main/discord-adblock.css);
        '';
      };
    };
}
