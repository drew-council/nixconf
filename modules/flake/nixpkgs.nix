{ inputs, lib, ... }:
let
  pkgsDir = ../../pkgs;

  # Every pkgs/<name>/package.nix becomes pkgs.<name>.
  localPackages =
    self: _:
    lib.mapAttrs (name: _: self.callPackage (pkgsDir + "/${name}/package.nix") { }) (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir pkgsDir)
    );
in
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = import inputs.systems;

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          # logseq hardcodes electron_39.
          permittedInsecurePackages = [ "electron-39.8.10" ];
        };
        overlays = [
          localPackages
          (import ./_overlay.nix { inherit inputs; })
          # builds against this flake's nixpkgs, including its Electron
          inputs.gchat-desktop.overlays.default
          inputs.t3code.overlays.default
        ];
      };
    };
}
