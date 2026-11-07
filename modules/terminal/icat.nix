{
  flake.modules.homeManager.terminal =
    { lib, pkgs, ... }:
    let
      # Works over ssh too, when the local terminal speaks the kitty image protocol.
      icat = pkgs.writeShellScriptBin "icat" ''
        exec ${lib.getExe pkgs.kitty} +kitten icat "$@"
      '';
    in
    {
      home.packages = [ icat ];
    };
}
