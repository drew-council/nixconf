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
  # One launcher at a time. A second one could restart desktop Steam while
  # game mode starts. --close keeps the lock out of the Steam it starts.
  text = ''
    status=0
    flock --close --timeout 20 --conflict-exit-code 75 "$XDG_RUNTIME_DIR/game-mode.lock" \
      nu ${./game-mode.nu} --config ${configJson} "$@" || status=$?
    if ((status == 75)); then
      notify-send "game-mode" "Game mode is already running." || true
    fi
    exit "$status"
  '';
}
