let
  lockScreenPic = builtins.fetchurl {
    url = "https://filedn.com/l0xkAHTdfcEJNc2OW7dfBny/lockscreen.png";
    sha256 = "1w3biszx1iy9qavr2cvl4gxrlf3lbrjpp50bp8wbi3rdpzjgv4kl";
  };
in
{
  flake.modules.nixos.desktop-linux =
    { config, pkgs, ... }:
    let
      sddmTheme = pkgs.stdenv.mkDerivation {
        name = "sddm-theme";
        src = pkgs.fetchFromGitHub {
          owner = "JaKooLit";
          repo = "simple-sddm-2";
          rev = "84ae7ad47eab5daa9d904b2e33669788d891bd3d";
          hash = "sha256-BkqtSh944QIVyYvXCCU8Pucs/2RpWXlwNFSC9zVlRoc=";
        };

        postPatch = ''
          ls
          substituteInPlace theme.conf \
          --replace-fail "WELCOME!" "${config.networking.hostName}" \
          --replace-fail "Backgrounds/mountain.png" "${lockScreenPic}" \
          --replace-fail "HH:mm" "hh:mm AP"
        '';

        installPhase = ''
          mkdir -p $out
          cp -R ./* $out/
        '';
      };
    in
    {
      catppuccin.sddm.enable = false;
      # Simple Desktop Display Manager
      services.displayManager.sddm = {
        extraPackages = with pkgs.kdePackages; [
          qt5compat
          qtdeclarative
          qtsvg
        ];
        enable = true;
        wayland.enable = true;
        package = pkgs.kdePackages.sddm;
        theme = "${sddmTheme}";
      };
    };
}
