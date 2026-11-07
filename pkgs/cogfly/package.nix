# Cogfly, a Silksong mod manager (Java jar release; needs Java 23+, zenity for
# Linux file pickers).
{
  copyDesktopItems,
  fetchurl,
  jdk25,
  lib,
  makeDesktopItem,
  makeWrapper,
  stdenvNoCC,
  zenity,
}:
stdenvNoCC.mkDerivation {
  pname = "cogfly";
  version = "1.2.5";

  src = fetchurl {
    url = "https://github.com/Nix-main/Cogfly/releases/download/1.2.5/Cogfly-1.2.5.jar";
    hash = "sha256-v0tfCmxezYe68n/gzbjYateRSGoNvAjBStAPZ6AUeHc=";
  };

  dontUnpack = true;

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "cogfly";
      exec = "cogfly";
      icon = "cogfly";
      desktopName = "Cogfly";
      genericName = "Silksong Mod Manager";
      categories = [
        "Game"
        "PackageManager"
      ];
    })
  ];

  installPhase = ''
    runHook preInstall

    install -Dm444 "$src" "$out/share/cogfly/cogfly.jar"
    makeWrapper "${jdk25}/bin/java" "$out/bin/cogfly" \
      --add-flags "-jar $out/share/cogfly/cogfly.jar" \
      --prefix PATH : "${lib.makeBinPath [ zenity ]}"

    # icon lives inside the jar at assets/icon.png
    mkdir icon
    (cd icon && ${jdk25}/bin/jar -xf "$src" assets/icon.png)
    install -Dm644 icon/assets/icon.png \
      "$out/share/icons/hicolor/128x128/apps/cogfly.png"

    runHook postInstall
  '';

  meta = {
    description = "Cross-platform mod manager for Hollow Knight: Silksong";
    homepage = "https://github.com/Nix-main/Cogfly";
    license = lib.licenses.mit;
    mainProgram = "cogfly";
    platforms = lib.platforms.unix;
  };
}
