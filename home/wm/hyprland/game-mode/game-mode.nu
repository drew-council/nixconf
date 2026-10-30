#!/usr/bin/env nu

# Switch from Hyprland to the gamescope game mode session on the TV, wait for
# it to end, then restore the desktop's monitor profile, audio, and Steam.

const unit = "game-mode.service"

def notify [body: string] {
  ^notify-send "game-mode" $body
}

def wait-until [timeout: duration check: closure]: nothing -> bool {
  let deadline = (date now) + $timeout
  while (date now) <= $deadline {
    if (do $check) { return true }
    sleep 500ms
  }
  false
}

def steam-running []: nothing -> bool {
  (^pgrep -u $env.USER -x steam | complete).exit_code == 0
}

def unit-state []: nothing -> string {
  ^systemctl show --property ActiveState --value $unit | str trim
}

def connector-connected [connector: string]: nothing -> bool {
  glob $"/sys/class/drm/card*-($connector)/status"
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
  ^hypr-monitor-profile (active-monitor-profile)
  if $steam_was_running {
    ^setsid -f steam -silent o+e> /dev/null
  }
}

def main [--config: path] {
  let cfg = open $config

  if (unit-state) in ["active" "activating" "deactivating"] {
    notify "Game mode is already running."
    return
  }
  if not (connector-connected $cfg.connector) {
    notify $"($cfg.connector) is not connected. Is the TV on?"
    return
  }

  let steam_was_running = steam-running
  if $steam_was_running {
    ^timeout 20 steam -shutdown o+e> /dev/null
    if not (wait-until 30sec { not (steam-running) }) {
      notify "Steam did not quit. Game mode not started."
      return
    }
  }

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
    ^switchaudio --wait 120 --alsa-name $audio.alsaName --card-name $audio.cardName --card-profile $audio.cardProfile
  }

  wait-until 3650day { (unit-state) not-in ["active" "activating" "deactivating"] } | ignore
  restore $steam_was_running
}
