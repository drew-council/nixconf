{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    {
      programs.bat = {
        enable = true;
        config = {
          style = "header-filename,rule,snip";
          color = "always";
        };
        syntaxes = {
          nushell.src = pkgs.fetchurl {
            url = "https://gist.githubusercontent.com/melMass/294c21a113d0bd329ae935a79879fe04/raw/nushell.sublime-syntax";
            hash = "sha256-QSjnGrv3o9qZ74b6Hk6pXJ6fx2Dq8U0cu9fyd51zokw=";
          };
        };
      };
    };
}
