#!/usr/bin/env nu

# Switch from Hyprland to the gamescope game mode session on the TV, wait for
# it to end, then restore the desktop's monitor profile, audio, and Steam.

const unit = "game-mode.service"

def notify [body: string] {
  ^notify-send "game-mode" $body | complete | ignore
}

def wait-until [timeout: duration check: closure]: nothing -> bool {
  let deadline = (date now) + $timeout
  while (date now) <= $deadline {
    if (do $check) { return true }
    sleep 500ms
  }
  false
}

# The client is the process that holds Steam's state. This is the check
# Steam's own launcher script uses.
def steam-client-running []: nothing -> bool {
  try {
    let pid = open --raw ($env.HOME | path join ".steam" "steam.pid") | str trim
    $pid =~ '^[0-9]+$' and (open --raw $"/proc/($pid)/comm" | str trim) == "steam"
  } catch {
    false
  }
}

# Steam's launcher, client, and helpers. The launcher and helpers outlive the
# client by minutes, so "has Steam quit" MUST NOT wait on them.
def steam-processes []: nothing -> list<int> {
  let steam_dir = $env.HOME | path join ".local" "share" "Steam"
  let procs = ^ps -u $env.USER -o pid=,ppid=,comm=,exe=
    | complete
    | get stdout
    | lines
    | parse --regex '^\s*(?<pid>\d+)\s+(?<ppid>\d+)\s+(?<comm>\S+)\s+(?<exe>.*)$'
    | update pid { into int }
    | update ppid { into int }

  let roots = $procs
    | where {|p| $p.comm == "steam" or ($p.exe | str starts-with $"($steam_dir)/") }
    | get pid

  # Add every descendant of a root.
  generate {|found|
    let more = $procs | where {|p| $p.ppid in $found and $p.pid not-in $found } | get pid
    if ($more | is-empty) { {out: $found} } else { {next: ($found ++ $more)} }
  } $roots
  | last
  | default []
}

def signal-steam [signal: string] {
  for pid in (steam-processes) {
    ^kill $"-($signal)" $pid | complete | ignore
  }
}

# Quit desktop Steam and leave no process of it behind. Game mode runs its own
# Steam, and two cannot share the install.
def stop-steam [] {
  if (steam-client-running) {
    try { ^timeout 20 steam -shutdown o+e> /dev/null }
    wait-until 30sec { not (steam-client-running) } | ignore
  }

  signal-steam "TERM"
  if not (wait-until 10sec { steam-processes | is-empty }) {
    signal-steam "KILL"
    wait-until 5sec { steam-processes | is-empty } | ignore
  }
}

def unit-state []: nothing -> string {
  ^systemctl show --property ActiveState --value $unit | complete | get stdout | str trim
}

def connector-connected [connector: string]: nothing -> bool {
  glob --follow-symlinks $"/sys/class/drm/card*-($connector)/status"
  | any {|status| (open --raw $status | str trim) == "connected" }
}

# gamescope creates its Wayland socket after it takes the output.
def gamescope-up [since: datetime]: nothing -> bool {
  glob $"($env.XDG_RUNTIME_DIR)/gamescope-[0-9]"
  | any {|socket| (ls -D $socket | get 0.modified) >= $since }
}

def active-monitor-profile []: nothing -> string {
  let state = $env.XDG_RUNTIME_DIR | path join "hyprmonitor-state.lua"
  if not ($state | path exists) { return "default" }
  open --raw $state
  | parse --regex 'active_profile = "(?<label>[^"]+)"'
  | get 0?.label
  | default "default"
}

def restore [steam_was_running: bool] {
  # Re-applying the profile also switches audio back.
  ^timeout 30 hypr-monitor-profile (active-monitor-profile) | complete | ignore
  if $steam_was_running {
    try { ^setsid -f steam -silent o+e> /dev/null }
  }
}

def main [--config: path] {
  let cfg = open $config
  # Steam's sandbox fails to start from a directory it cannot see.
  cd $env.HOME

  if (unit-state) in ["active" "activating" "deactivating"] {
    notify "Game mode is already running."
    return
  }
  if not (connector-connected $cfg.connector) {
    notify $"($cfg.connector) is not connected. Is the TV on?"
    return
  }

  let steam_was_running = steam-client-running
  if $steam_was_running { notify "Closing Steam, then starting game mode." }
  stop-steam

  let started = date now
  let start = ^systemctl start $unit | complete
  if $start.exit_code != 0 {
    notify $"Failed to start game mode: ($start.stderr | str trim)"
    restore $steam_was_running
    return
  }

  # The TV's HDMI audio device resets when gamescope sets the mode, so switch
  # audio only after gamescope is up.
  if (wait-until 20sec { gamescope-up $started }) {
    sleep 2sec
    let audio = $cfg.audio
    let switched = ^switchaudio --wait 30 --alsa-name $audio.alsaName --card-name $audio.cardName --card-profile $audio.cardProfile | complete
    if $switched.exit_code != 0 {
      notify $"TV audio not selected: ($switched.stderr | str trim)"
    }
  }

  wait-until 3650day { (unit-state) not-in ["active" "activating" "deactivating"] } | ignore
  restore $steam_was_running
}
