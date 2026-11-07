{
  config,
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    {
      packages = {
        nvim = inputs.nixvim.legacyPackages.${system}.makeNixvim (
          import ../terminal/nvim/_config.nix { inherit pkgs; }
        );
        topiary-nushell = inputs.topiary-nushell.packages.${system}.default;
        inherit (pkgs) linear-cli ntn;
      };

      checks = {
        linear-cli = pkgs.runCommand "linear-cli-check" { nativeBuildInputs = [ pkgs.linear-cli ]; } ''
          linear --version > "$out"
        '';
        ntn = pkgs.runCommand "ntn-check" { nativeBuildInputs = [ pkgs.ntn ]; } ''
          ntn --version > "$out"
        '';
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin (
        let
          macos = config.flake.darwinConfigurations.macos.config;
        in
        {
          darwin-system = macos.system.build.toplevel;
          home-manager = macos.home-manager.users.${config.my.user.name}.home.activationPackage;
          inherit (pkgs) herdr-keybinds;
        }
      );
    };
}
