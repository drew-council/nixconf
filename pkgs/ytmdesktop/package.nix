# YouTube Music Desktop App, repackaged from upstream release binaries.
# nixpkgs still ships 2.0.12, which hangs or degrades on YTM's current player:
# https://github.com/ytmdesktop/ytmdesktop/issues/1819
# 2.1.0 moved to pnpm and a native module, so nixpkgs cannot bump it trivially.
# Remove once nixpkgs ships 2.1.0 or later.
{
  asar,
  autoPatchelfHook,
  copyDesktopItems,
  dpkg,
  electron_45,
  fetchurl,
  lib,
  makeDesktopItem,
  makeWrapper,
  stdenv,
  stdenvNoCC,
  unzip,
}:
let
  pname = "ytmdesktop";
  version = "2.1.0";
  releaseUrl = "https://github.com/ytmdesktop/ytmdesktop/releases/download/v${version}";

  meta = {
    changelog = "https://github.com/ytmdesktop/ytmdesktop/releases/tag/v${version}";
    description = "Desktop App for YouTube Music";
    homepage = "https://ytmdesktop.app/";
    license = lib.licenses.gpl3Only;
    mainProgram = "ytmdesktop";
    platforms = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };

  linux = stdenv.mkDerivation {
    inherit pname version meta;

    src = fetchurl {
      url = "${releaseUrl}/youtube-music-desktop-app_${version}_amd64.deb";
      hash = "sha256-20BAsUae8hTtdDhpXx3/Ytsyac2QimptBKcXZMi75tg=";
    };

    nativeBuildInputs = [
      asar
      autoPatchelfHook
      copyDesktopItems
      dpkg
      makeWrapper
    ];

    # The xosms MPRIS module links libgcc_s.
    buildInputs = [ (lib.getLib stdenv.cc.cc) ];

    unpackPhase = ''
      runHook preUnpack
      # Only resources/ is used; a full extract fails on setuid chrome-sandbox.
      dpkg-deb --fsys-tarfile $src | tar -x --wildcards './usr/lib/*/resources'
      runHook postUnpack
    '';

    # Under nixpkgs' electron, the binary is named "electron", so
    # app.isPackaged is false and process.resourcesPath is electron's own.
    # The app then loads dev-server URLs and opens DevTools.
    buildPhase = ''
      runHook preBuild

      res=usr/lib/youtube-music-desktop-app/resources
      asar extract $res/app.asar app
      substituteInPlace app/.vite/main/index.cjs \
        --replace-fail "f.app.isPackaged" "!0" \
        --replace-fail "process.resourcesPath" "\"$out/share/ytmdesktop/resources\""
      rm -r $res/app.asar $res/app.asar.unpacked
      asar pack app $res/app.asar --unpack "*.node"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/ytmdesktop
      cp -r $res $out/share/ytmdesktop/resources
      install -Dm644 $res/ytmd.png $out/share/pixmaps/ytmdesktop.png

      makeWrapper ${lib.getExe electron_45} $out/bin/ytmdesktop \
        --add-flags $out/share/ytmdesktop/resources/app.asar \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

      runHook postInstall
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "ytmdesktop";
        desktopName = "YouTube Music Desktop App";
        genericName = meta.description;
        exec = "ytmdesktop %U";
        icon = "ytmdesktop";
        mimeTypes = [ "x-scheme-handler/ytmd" ];
        categories = [
          "AudioVideo"
          "Audio"
        ];
        startupNotify = true;
        startupWMClass = "YouTube Music Desktop App";
      })
    ];
  };

  darwin = stdenvNoCC.mkDerivation {
    inherit pname version meta;

    src = fetchurl {
      url = "${releaseUrl}/YouTube.Music.Desktop.App-darwin-arm64-${version}.zip";
      hash = "sha256-OTRCPDfLGnEpbdMc6px9uc8wTBtXJsRn/Hj7a/TOoeI=";
    };

    nativeBuildInputs = [ unzip ];

    sourceRoot = ".";

    # Patching the signed bundle would break its code signature.
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications $out/bin
      cp -r "YouTube Music Desktop App.app" $out/Applications
      ln -s "$out/Applications/YouTube Music Desktop App.app/Contents/MacOS/youtube-music-desktop-app" $out/bin/ytmdesktop
      runHook postInstall
    '';
  };
in
if stdenv.hostPlatform.isDarwin then darwin else linux
