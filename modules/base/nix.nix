let
  substitutersConfig = builtins.fromJSON (builtins.readFile ../../substituters_config.json);
in
{
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    {
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        trusted-users = [
          "root"
          "@wheel"
        ];
      }
      // lib.getAttrs [
        "extra-substituters"
        "extra-trusted-substituters"
        "extra-trusted-public-keys"
      ] substitutersConfig;

      programs.nix-ld.enable = true;

      # Preserve root-level scheduled cleanup without installing nh into the system
      # profile; Home Manager owns the interactive command and default flake.
      programs.nh = {
        package = pkgs.nh-cachix;
        clean.enable = true;
        clean.extraArgs = "--keep-since 10d";
      };
    };
}
