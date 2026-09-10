{
  description = "NixOS, nix-darwin, and Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # secrets management through 1Password
    opnix.url = "github:brizzbuzz/opnix";

    catppuccin.url = "github:catppuccin/nix";
    hyprland.url = "github:hyprwm/Hyprland";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    nix-project-generator = {
      url = "github:drew-council/nix-project-template";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    weave = {
      url = "github:drew-council/weave/drew-council-tweaks";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    };

    tdx = {
      url = "github:niklas-heer/tdx";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tuicr = {
      url = "github:drew-council/tuicr/bizmythy-tweaks";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    systems = {
      url = "path:./flake.systems.nix";
      flake = false;
    };

    topiary-nushell = {
      url = "github:drew-council/topiary-nushell-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    { nixpkgs, self, ... }@inputs:
    let
      lib = nixpkgs.lib;

      nixpkgsSettings = {
        config.allowUnfree = true;
        config.permittedInsecurePackages = [
          "electron-39.8.10"
        ];
        overlays = [
          (import ./overlays.nix { inherit inputs; })
        ];
      };

      eachSystem =
        f:
        lib.genAttrs (import inputs.systems) (
          system:
          f (
            import nixpkgs (
              {
                inherit system;
              }
              // nixpkgsSettings
            )
          )
        );

      treefmtEval = eachSystem (
        pkgs:
        inputs.treefmt-nix.lib.evalModule pkgs {
          imports = [
            inputs.topiary-nushell.treefmtModules.default
            ./treefmt.nix
          ];
        }
      );

      buildConfig = builtins.fromJSON (builtins.readFile ./build_config.json);

      mkVars =
        {
          home,
          defaults,
        }:
        rec {
          user = "drew";
          inherit home defaults;
          flakePath = "${home}/nixconf";
          hmBackupFileExtension = "hmbackup";
          lockScreenPic = builtins.fetchurl {
            url = "https://filedn.com/l0xkAHTdfcEJNc2OW7dfBny/lockscreen.png";
            sha256 = "1w3biszx1iy9qavr2cvl4gxrlf3lbrjpp50bp8wbi3rdpzjgv4kl";
          };
          isPersonal = _: true;
        };

      linuxVars = mkVars {
        home = "/home/drew";
        defaults = {
          tty = "ghostty";
          fileManager = "dolphin";
          browser = "zen-beta";
          calculator = "qalculate-qt";
          editor = "zeditor --new";
          termEditor = "nvim";
          shell = "nu";
        };
      };

      darwinVars = mkVars {
        home = "/Users/drew";
        defaults = {
          tty = "Terminal";
          fileManager = "open";
          browser = "open";
          calculator = "open -a Calculator";
          editor = "nvim";
          termEditor = "nvim";
          shell = "nu";
        };
      };

      mkHomeManager =
        {
          isLinux,
          vars,
        }:
        {
          home-manager = {
            extraSpecialArgs = {
              inherit inputs vars;
              platform = {
                inherit isLinux;
                isDarwin = !isLinux;
              };
            };
            backupFileExtension = vars.hmBackupFileExtension;
            users.${vars.user} = {
              nixpkgs = nixpkgsSettings;
              imports = [
                inputs.nix-index-database.homeModules.default
                inputs.nixvim.homeModules.nixvim
                ./home
              ]
              ++ lib.optionals isLinux [
                inputs.catppuccin.homeModules.catppuccin
                inputs.opnix.homeManagerModules.default
              ];
            };
          };
        };

      linuxHome = mkHomeManager {
        isLinux = true;
        vars = linuxVars;
      };
      darwinHome = mkHomeManager {
        isLinux = false;
        vars = darwinVars;
      };

      getPcConfig =
        hostname:
        lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            vars = linuxVars;
          };
          modules = [
            {
              nixpkgs = nixpkgsSettings // {
                hostPlatform = "x86_64-linux";
              };
              networking.hostName = hostname;
            }

            inputs.catppuccin.nixosModules.catppuccin
            inputs.nix-flatpak.nixosModules.nix-flatpak
          ]
          ++ [
            ./modules/base.nix
            ./hosts/${hostname}/configuration.nix
            inputs.home-manager.nixosModules.home-manager
            linuxHome
          ];
        };

      pcConfigs = lib.genAttrs buildConfig.hosts getPcConfig;

      getServerConfig =
        hostname:
        lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            vars = linuxVars;
          };
          modules = [
            {
              nixpkgs = nixpkgsSettings // {
                hostPlatform = "x86_64-linux";
              };
              networking.hostName = hostname;
            }

            ./modules/server.nix
            ./hosts/${hostname}/configuration.nix
          ];
        };

      serverConfigs = lib.genAttrs [ "nixos-0" ] getServerConfig;
      configs = pcConfigs // serverConfigs;

      darwinConfig = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit inputs;
          vars = darwinVars;
        };
        modules = [
          {
            nixpkgs = nixpkgsSettings // {
              hostPlatform = "aarch64-darwin";
            };
          }
          ./hosts/macos/configuration.nix
          inputs.home-manager.darwinModules.home-manager
          darwinHome
        ];
      };
    in
    {
      nixosConfigurations = configs;
      darwinConfigurations.macos = darwinConfig;

      packages = eachSystem (pkgs: {
        nvim = inputs.nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system}.makeNixvim (
          import ./nixvim.nix { inherit pkgs; }
        );
        topiary-nushell = inputs.topiary-nushell.packages.${pkgs.stdenv.hostPlatform.system}.default;
        linear-cli = pkgs.linear-cli;
      });

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper);

      checks = eachSystem (
        pkgs:
        {
          formatting = treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
          linear-cli = pkgs.runCommand "linear-cli-check" { nativeBuildInputs = [ pkgs.linear-cli ]; } ''
            linear --version > "$out"
          '';
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          darwin-system = darwinConfig.config.system.build.toplevel;
          home-manager = darwinConfig.config.home-manager.users.${darwinVars.user}.home.activationPackage;
          herdr-keybinds = pkgs.herdr-keybinds;
        }
      );
    };
}
