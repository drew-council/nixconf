{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      fonts = {
        enableDefaultPackages = true;
        packages =
          (with pkgs.nerd-fonts; [
            jetbrains-mono
            hack
            fira-code
            ubuntu-mono
            departure-mono
          ])
          ++ (with pkgs; [
            noto-fonts
            noto-fonts-color-emoji
            ibm-plex
          ]);

        fontconfig = {
          enable = true;
          defaultFonts = {
            monospace = [ "JetBrainsMono Nerd Font" ];
            sansSerif = [ "Noto Sans" ];
            serif = [ "Noto Serif" ];
          };
        };
      };
    };

  flake.modules.homeManager.desktop.fonts.fontconfig.enable = true;
}
