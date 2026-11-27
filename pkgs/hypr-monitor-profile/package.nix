{
  buildGo126Module,
  fuzzel,
  hyprland,
  lib,
  libnotify,
  makeWrapper,
  profilesJson ? throw "hypr-monitor-profile needs profilesJson",
}:

buildGo126Module {
  pname = "hypr-monitor-profile";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/hypr-monitor-profile" \
      --add-flags "--profiles-json ${profilesJson}" \
      --prefix PATH : "${
        lib.makeBinPath [
          fuzzel
          hyprland
          libnotify
        ]
      }"
  '';

  meta = {
    description = "Select a Hyprland monitor profile";
    license = lib.licenses.mit;
    mainProgram = "hypr-monitor-profile";
  };
}
