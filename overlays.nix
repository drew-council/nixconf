{ inputs }:

self: super:
let
  hyprlandPackages = import ./pkgs/hyprland-upstream.nix {
    pkgs = super;
    inherit inputs;
  };
in
{
  aquamarine = hyprlandPackages.aquamarine;
  hyprland = hyprlandPackages.hyprland;
  xdg-desktop-portal-hyprland = hyprlandPackages.xdg-desktop-portal-hyprland;

  # Use rocmPackages from nixpkgs-stable to avoid crashes with unstable
  rocmPackages =
    inputs.nixpkgs-stable.legacyPackages.${super.stdenv.hostPlatform.system}.rocmPackages;
  python3Packages = super.python3Packages.overrideScope (
    python-self: python-super: {
      hyprpy = super.callPackage ./pkgs/hyprpy.nix { };
    }
  );

  protobuf-language-server = super.callPackage ./pkgs/protobuf-language-server.nix { };
  herdr-keybinds = super.callPackage ./home/programs/herdr/keybinds-plugin/package.nix { };
  herdr-web = super.callPackage ./pkgs/herdr-web { };
  lg-herdr-watch =
    super.runCommand "lg-herdr-watch-0.1.0"
      {
        meta = with super.lib; {
          description = "Restart lazygit when the focused Herdr workspace changes";
          license = licenses.mit;
          platforms = platforms.unix;
          mainProgram = "lg-herdr-watch";
        };
      }
      ''
        mkdir -p "$out/bin"
        ln -s "${self.herdr-keybinds}/bin/lg-herdr-watch" "$out/bin/lg-herdr-watch"
      '';
  tdx =
    let
      package = inputs.tdx.packages.${super.stdenv.hostPlatform.system}.default;
    in
    if super.stdenv.hostPlatform.isLinux then
      # Upstream uses macOS pbcopy/pbpaste; replace it with Wayland clipboard
      # commands only on Linux.
      package.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [ ./pkgs/tdx-clipboard-linux.patch ];
        nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ super.makeWrapper ];
        postInstall = (oldAttrs.postInstall or "") + ''
          wrapProgram $out/bin/tdx \
            --prefix PATH : ${super.lib.makeBinPath [ super.wl-clipboard ]}
        '';
      })
    else
      package;
  tuicr =
    let
      naersk = super.callPackage inputs.tuicr.inputs.naersk { };
    in
    naersk.buildPackage {
      src = inputs.tuicr;

      # The crates.io API download endpoint intermittently returns 403. This
      # mirror implements the same API; Cargo.lock still verifies every crate.
      cratesDownloadUrl = "https://rsproxy.cn/api/v1/crates";
    };
  nu-plugin-toon = super.callPackage ./pkgs/nu_plugin_toon.nix { };
  linear-cli = super.callPackage ./pkgs/linear-cli.nix { };

  ntn = super.callPackage ./pkgs/ntn.nix { };
  nh-cachix = super.callPackage ./pkgs/nh-cachix.nix { };

  amd-ctk = super.callPackage ./pkgs/amd-ctk.nix { };
  amd-container-runtime = super.callPackage ./pkgs/amd-container-runtime.nix { };

  # nixpkgs version takes forever to build all the driver versions
  nvtop-appimage =
    let
      pname = "nvtop";
      version = "3.2.0";
      src = super.fetchurl {
        url = "https://github.com/Syllo/nvtop/releases/download/3.2.0/${pname}-${version}-x86_64.AppImage";
        hash = "sha256-M8VPtwJfQ6IT246YMIhg1ADbM0mmH8k4L+RzbH0lgMQ=";
      };
    in
    super.appimageTools.wrapType2 {
      inherit pname version src;
      meta.platforms = [ "x86_64-linux" ];
    };

  # ytmdesktop 2.0.12 fixes a failure to hook YouTube Music that caused an
  # endless "taking longer to start than expected" loading screen
  # (https://github.com/ytmdesktop/ytmdesktop/issues/1807). Drop once nixpkgs bumps.
  ytmdesktop =
    let
      newSrc = super.fetchFromGitHub {
        owner = "ytmdesktop";
        repo = "ytmdesktop";
        tag = "v2.0.12";
        leaveDotGit = true;
        postFetch = ''
          cd $out
          git rev-parse HEAD > .COMMIT
          find -name .git -print0 | xargs -0 rm -rf
        '';
        hash = "sha256-fT5UdJ9YYK3hXC8GkEeJ/LK1bCyXofcKA0aCJUnjZdk=";
      };
    in
    super.ytmdesktop.overrideAttrs (oldAttrs: {
      version = "2.0.12";
      src = newSrc;
      yarnOfflineCache = super.yarn-berry_4.fetchYarnBerryDeps {
        src = newSrc;
        missingHashes = oldAttrs.missingHashes;
        patches = oldAttrs.patches;
        hash = "sha256-fpvBE4QZcDaWGgqU3jQlOe+bOLtnDEVNR4IuKBo35BQ=";
      };
    });

  # this package takes an *extremely* long time to check through all the files
  catppuccin-papirus-folders = super.catppuccin-papirus-folders.overrideAttrs (
    finalAttrs: previousAttrs: {
      doCheck = false;
    }
  );
}
