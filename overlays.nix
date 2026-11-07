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

  # nixpkgs lags upstream, and home/wm/omniwm/defaults.toml must match the
  # settings schema of the running version. Recapture it when bumping.
  omniwm = super.omniwm.overrideAttrs (oldAttrs: {
    version = "0.7.2";
    src = super.fetchurl {
      url = "https://github.com/OmniNull/OmniWM/releases/download/v0.7.2/OmniWM-v0.7.2.zip";
      hash = "sha256-wVPdL16U4JC4WG2E1AR5qv2AA44JOSNfMMS4Zyk3+8E=";
    };
  });

  herdr-keybinds = super.callPackage ./home/programs/herdr/keybinds-plugin/package.nix { };
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
      package.overrideAttrs (oldAttrs: {
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
  linear-cli = super.callPackage ./pkgs/linear-cli.nix { };

  ntn = super.callPackage ./pkgs/ntn.nix { };
  nh-cachix = super.callPackage ./pkgs/nh-cachix.nix { };

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
}
