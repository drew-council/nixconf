{
  coreutils,
  libnotify,
  nushell,
  procps,
  switchaudio,
  systemd,
  util-linux,
  writeShellApplication,
  configJson ? throw "game-mode needs configJson",
}:
writeShellApplication {
  name = "game-mode";
  runtimeInputs = [
    coreutils
    libnotify
    nushell
    procps
    systemd
    util-linux
    switchaudio
  ];
  text = ''
    exec nu ${./game-mode.nu} --config ${configJson} "$@"
  '';
}
