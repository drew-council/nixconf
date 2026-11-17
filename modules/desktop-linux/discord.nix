{
  flake.modules.homeManager.desktop-linux =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.discord ];
    };
}
