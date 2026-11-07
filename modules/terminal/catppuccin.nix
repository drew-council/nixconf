{ inputs, ... }:
{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) isLinux;
    in
    {
      imports = [ inputs.catppuccin.homeModules.catppuccin ];

      catppuccin = {
        enable = isLinux;
        autoEnable = isLinux;
        flavor = "mocha";
        mako.enable = false;
      };
    };
}
