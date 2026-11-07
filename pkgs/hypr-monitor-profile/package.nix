{
  fuzzel,
  hyprland,
  lib,
  libnotify,
  python3,
  writeShellApplication,
  profilesJson ? throw "hypr-monitor-profile needs profilesJson",
}:
let
  python = python3.withPackages (pythonPackages: [ pythonPackages.click ]);
in
writeShellApplication {
  name = "hypr-monitor-profile";
  runtimeInputs = [
    fuzzel
    hyprland
    libnotify
    python
  ];
  text = ''
    exec ${lib.getExe python} ${./hypr-monitor-profile.py} --profiles-json ${profilesJson} "$@"
  '';
}
