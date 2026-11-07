{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    {
      # Works over ssh too, when the local terminal speaks the kitty image protocol.
      home.packages = [ pkgs.icat ];
    };
}
