# Turns `hosts.<name>` entries into NixOS and nix-darwin configurations. Each
# name in `features` selects `flake.modules.<class>.<name>` and
# `flake.modules.homeManager.<name>`, whichever exist.
{
  config,
  inputs,
  lib,
  withSystem,
  ...
}:
let
  inherit (config.flake) modules;
  inherit (lib) mkOption types;

  knownFeatures = lib.concatMap lib.attrNames (lib.attrValues modules);

  # Declared in every module class, so the same `config.my.*` reads work in
  # NixOS, nix-darwin, and Home Manager modules.
  myModule = name: host: {
    options.my = {
      user = mkOption { type = types.attrs; };
      host = mkOption { type = types.attrs; };
    };

    config.my = {
      user =
        let
          home = "/${if isDarwin host then "Users" else "home"}/${config.my.user.name}";
        in
        config.my.user
        // {
          inherit home;
          flakePath = "${home}/nixconf";
          workDir = "${home}/work";
        };
      host = {
        inherit name;
        inherit (host) display features;
      };
    };
  };

  isDarwin = host: lib.hasSuffix "-darwin" host.system;

  selectModules =
    class: host:
    lib.concatMap (feature: lib.optional (modules.${class} ? ${feature}) modules.${class}.${feature}) (
      host.features
    );

  mkHostModule =
    class: name: host:
    let
      unknown = lib.subtractLists knownFeatures host.features;
    in
    assert lib.assertMsg (
      unknown == [ ]
    ) "hosts.${name}: unknown features: ${lib.concatStringsSep ", " unknown}";
    {
      imports = selectModules class host ++ [
        host.module
        (myModule name host)
        inputs.home-manager."${class}Modules".home-manager
      ];

      nixpkgs = {
        hostPlatform = host.system;
        pkgs = withSystem host.system ({ pkgs, ... }: pkgs);
      };

      networking.hostName = name;

      home-manager = {
        useGlobalPkgs = true;
        inherit (config.my.user) backupFileExtension;
        users.${config.my.user.name}.imports = selectModules "homeManager" host ++ [
          (myModule name host)
        ];
      };
    };

  hostsOf = predicate: lib.filterAttrs (_: predicate) config.hosts;
in
{
  options.hosts = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          system = mkOption { type = types.str; };
          features = mkOption { type = types.listOf types.str; };
          display = mkOption {
            type = types.attrs;
            default = { };
            description = "Monitor and audio data read by the desktop features.";
          };
          module = mkOption {
            type = types.deferredModule;
            default = { };
            description = "Configuration specific to this machine.";
          };
        };
      }
    );
    default = { };
  };

  config.flake = {
    nixosConfigurations = lib.mapAttrs (
      name: host: inputs.nixpkgs.lib.nixosSystem { modules = [ (mkHostModule "nixos" name host) ]; }
    ) (hostsOf (host: !isDarwin host));

    darwinConfigurations = lib.mapAttrs (
      name: host: inputs.nix-darwin.lib.darwinSystem { modules = [ (mkHostModule "darwin" name host) ]; }
    ) (hostsOf isDarwin);
  };
}
