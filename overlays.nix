{ inputs }:

self: super: {
  herdr-keybinds = super.callPackage ./home/programs/herdr/keybinds-plugin/package.nix { };
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
  tuicr = inputs.tuicr.packages.${super.stdenv.hostPlatform.system}.default;
  linear-cli = super.callPackage ./pkgs/linear-cli.nix { };

  ntn = super.callPackage ./pkgs/ntn.nix { };
  nh-cachix = super.callPackage ./pkgs/nh-cachix.nix { };

}
