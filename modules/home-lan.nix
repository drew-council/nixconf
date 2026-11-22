{ inputs, ... }:
let
  # niks3 binary cache on tungsten (tungsten-config services/nix-cache).
  nixCachePublicKey = "tungsten-nix-cache-1:xDf2GoqcK1M0Qd8PgghmO/PeOepTVUjIcEADqpc+Mig=";
  nixCacheTokenPath = "niks3/auth-token";

  # Same key as in desktop/voxtype.nix, so hosts with both import opnix once.
  opnixHomeModule = {
    key = "opnix-home-manager";
    imports = [ inputs.opnix.homeManagerModules.default ];
  };
in
{
  flake.modules.nixos.home-lan =
    { config, lib, ... }:
    let
      cfg = config.my.nixCache;
    in
    {
      imports = [ inputs.niks3.nixosModules.niks3-auto-upload ];

      options.my.nixCache = {
        url = lib.mkOption {
          type = lib.types.str;
          default = "http://192.168.1.202:5751";
          description = "niks3 URL, used as both substituter and push server.";
        };
        push = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Upload every local build and its closure.
            niks3 presigns uploads for the LAN address of tungsten,
            so pushing only works from the home LAN.
          '';
        };
      };

      config = {
        networking.nameservers = [
          "1.1.1.1"
          "8.8.8.8"
        ];

        # Mount NAS, optional for boot
        fileSystems."/mnt/tungsten-vault" = {
          device = "192.168.1.202:/mnt/tungsten/tungsten-vault";
          fsType = "nfs";
          options = [
            "x-systemd.automount"
            "noauto"
          ];
        };

        nix.settings = {
          extra-substituters = [ cfg.url ];
          extra-trusted-public-keys = [ nixCachePublicKey ];
          # Skip quickly past an unreachable cache instead of curl's default.
          connect-timeout = 5;
        };

        # The post-build hook queues every local build.
        # The system toplevel is always built locally,
        # so each switch uploads the whole system closure.
        services.niks3-auto-upload = lib.mkIf cfg.push {
          enable = true;
          serverUrl = cfg.url;
          authTokenFile = "${config.my.user.home}/.config/${nixCacheTokenPath}";
        };
      };
    };

  flake.modules.homeManager.home-lan =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = osConfig.my.nixCache;
    in
    {
      imports = [ opnixHomeModule ];

      config = lib.mkIf cfg.push {
        # Home Manager writes the token; the root upload daemon reads it.
        programs.onepassword-secrets = {
          enable = true;
          tokenFile = "/etc/opnix-token";
          secrets.niks3Token = {
            reference = "op://opnix/tungsten-nix-cache/credential";
            path = "${config.xdg.configHome}/${nixCacheTokenPath}";
            mode = "0600";
          };
        };

        # Client for manual push, pins and gc.
        # It reads the token from its default path, the one above.
        home.packages = [ inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3 ];
        home.sessionVariables.NIKS3_SERVER_URL = cfg.url;
      };
    };
}
