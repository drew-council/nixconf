# Overrides of packages this flake does not own. Every workaround here MUST link
# its upstream issue and state when it can be removed.
{ inputs }:

_: super: {
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
}
