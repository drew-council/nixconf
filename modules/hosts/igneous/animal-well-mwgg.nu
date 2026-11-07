#!/usr/bin/env nix-shell
#! nix-shell -i nu
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5.tar.gz
#! nix-shell -p nushell wineWow64Packages.stagingFull curl

# Wine 11.14 returns a malformed OpenGL extension string that crashes Kivy when
# the client displays a connection error. Keep using the last working Wine
# release (11.12) until that regression is fixed upstream.

# Kivy logs this once its render loop draws the first frame. If it never
# appears, the client window is stuck black (see start-client-checked).
const kivy_first_frame_marker = "GL: NPOT texture support is available"
const client_gui_timeout = 30
const client_max_attempts = 3
const mwgg_version = "0.7.263"
const mwgg_installer_url = "https://github.com/MultiworldGG/MultiworldGG/releases/download/0.7.263/Setup.MultiworldGG.0.7.263.exe"
const mwgg_installer_sha256 = "5c4d9694ab36ac01971933a6eac44863bac4182afb742a1db15107c372e5b532"
const default_game_dir = "~/.local/share/Steam/steamapps/common/Animal Well"
const port = "56744"
let default_connection = $"mwgg://multiworld.gg:($port)"
const default_slot = "bizmyth"

def wine-prefix [] {
  $env.HOME | path join ".local/share/animal-well-mwgg"
}

def mwgg-launcher [] {
  wine-prefix
  | path join "drive_c/Program Files/MultiworldGG/MultiworldGGLauncher.exe"
}

def installer-path [] {
  let cache_home = ($env.XDG_CACHE_HOME? | default ($env.HOME | path join ".cache"))
  $cache_home | path join $"animal-well-mwgg/Setup.MultiworldGG.($mwgg_version).exe"
}

def log-path [name: string] {
  let state_home = ($env.XDG_STATE_HOME? | default ($env.HOME | path join ".local/state"))
  let log_dir = ($state_home | path join "animal-well-mwgg")
  mkdir $log_dir
  $log_dir | path join $"($name).log"
}

def new-log [name: string] {
  let log = (log-path $name)
  $"Started (date now)\n" | save --force $log
  $log
}

def run-in-prefix [log: path executable: string ...args: string] {
  with-env {WINEPREFIX: (wine-prefix)} {
    ^$executable ...$args o+e>> $log
  }
}

def require-file [file: path description: string] {
  if not ($file | path exists) {
    error make {msg: $"($description) was not found at ($file)"}
  }
}

def verified-installer [log: path] {
  let installer = (installer-path)
  mkdir ($installer | path dirname)

  let existing_hash = if ($installer | path exists) {
    ^sha256sum $installer | split row " " | first
  } else {
    null
  }

  if $existing_hash != $mwgg_installer_sha256 {
    print $"Downloading MultiworldGG ($mwgg_version)..."
    ^curl --fail --location --output $installer $mwgg_installer_url o+e>> $log
  }

  let actual_hash = (^sha256sum $installer | split row " " | first)
  if $actual_hash != $mwgg_installer_sha256 {
    error make {msg: $"MultiworldGG installer checksum mismatch: ($actual_hash)"}
  }

  $installer
}

def newest-client-log [] {
  let dir = (mwgg-launcher | path dirname | path join "logs")
  let logs = (try { ls $"($dir)/*" | where name =~ "AnimalWellClient_" } catch { [] })
  if ($logs | is-empty) { null } else { $logs | sort-by modified | reverse | first | get name }
}

def client-gui-ready [] {
  let log = (newest-client-log)
  if $log == null { return false }
  open --raw $log | str contains $kivy_first_frame_marker
}

def start-client [connection?: string] {
  let launcher = (mwgg-launcher)
  require-file $launcher "MultiworldGG launcher"
  let connection = ($connection | default $default_connection)
  let log = (new-log "client")

  print $"Connecting to multiworld.gg:($port); enter slot `($default_slot)` when prompted."
  print $"MultiworldGG output: ($log)"
  cd ($launcher | path dirname)
  run-in-prefix $log wine $launcher "ANIMAL WELL Client" $connection
}

# Launch the client in the background and wait until its window has actually
# rendered a first frame. Starting the client while the game's Wine dinput
# thread is enumerating HID devices can deadlock SDL2's joystick init, leaving
# the client window black; the Kivy first-frame marker in the log proves the
# window survived that race, so restart the client until it does.
def start-client-checked [connection: string] {
  let launcher = (mwgg-launcher)
  require-file $launcher "MultiworldGG launcher"
  let log = (new-log "client")

  print $"Connecting to multiworld.gg:($port); enter slot `($default_slot)` when prompted."
  print $"MultiworldGG output: ($log)"
  cd ($launcher | path dirname)

  mut attempt = 0
  while $attempt < $client_max_attempts {
    $attempt += 1
    job spawn { run-in-prefix $log wine $launcher "ANIMAL WELL Client" $connection }

    mut ready = false
    for _ in 1..$client_gui_timeout {
      sleep 1sec
      if (client-gui-ready) {
        $ready = true
        break
      }
    }
    if $ready { return }

    let attempt_msg = $"attempt ($attempt) of ($client_max_attempts)"
    print $"Client window failed to initialize (($attempt_msg)); restarting..."
    ^pkill -f MultiworldGGLauncher o+e>> $log
    sleep 3sec
  }
  print "Warning: client window may be black; close it and run the script again."
}

def client-running [] {
  (do { ^pgrep -f MultiworldGGLauncher } | complete).exit_code == 0
}

# Stay alive until the client exits so the background job is not reaped with
# this script's shell.
def wait-for-client [] {
  while (client-running) { sleep 2sec }
}

# Download and silently install the Windows MultiworldGG build in an isolated
# Wine prefix. Re-run this after changing the pinned version above.
def "main install" [] {
  let log = (new-log "install")
  let installer = (verified-installer $log)
  mkdir (wine-prefix)
  print $"Installer output: ($log)"
  run-in-prefix $log wineboot -- --init
  run-in-prefix $log wine $installer /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-

  require-file (mwgg-launcher) "MultiworldGG launcher"
  print $"MultiworldGG ($mwgg_version) is installed in (wine-prefix)."
}

# Open the full launcher for configuration, generation, and other tools.
def "main launcher" [] {
  let launcher = (mwgg-launcher)
  require-file $launcher "MultiworldGG launcher (run `animal-well-mwgg.nu install` first)"
  let log = (new-log "launcher")
  print $"MultiworldGG output: ($log)"
  cd ($launcher | path dirname)
  run-in-prefix $log wine $launcher
}

# Open only the ANIMAL WELL client. You can optionally pass the room's
# archipelago:// connection URI.
def "main client" [connection?: string] {
  start-client $connection
}

# Start the Steam-installed game and MWGG client in the same Wine prefix. The
# client is started first and only once its window is confirmed drawing does
# the game launch; the reverse order deadlocks the client's SDL2 joystick init
# against the game's dinput HID enumeration and renders its window black.
def main [
  connection?: string
  --game-dir: path = $default_game_dir
] {
  let game_dir = ($game_dir | path expand)
  let game = ($game_dir | path join "Animal Well.exe")
  require-file $game "ANIMAL WELL executable"
  require-file (mwgg-launcher) "MultiworldGG launcher (run `animal-well-mwgg.nu install` first)"

  start-client-checked ($connection | default $default_connection)

  let game_log = (new-log "game")
  print $"Animal Well output: ($game_log)"
  cd $game_dir
  run-in-prefix $game_log wine start /unix $game
  wait-for-client
}
