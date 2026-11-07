#!/usr/bin/env nu

def get_monitors [] {
  hyprctl monitors all -j | from json
}

def main [] {
  get_monitors | explore
}

def select_monitor [] {
  let monitors = get_monitors
  # select a monitor with fuzzel
  let selection_index = (
    $monitors | each {|monitor|
      let emoji = if $monitor.disabled { "❌" } else { "✅" }
      $"($emoji) ($monitor.name | fill --width 10)($monitor.description)"
    } | str join "\n" | fuzzel --dmenu --index --use-bold --width=60 --lines=5 | into int
  )
  $monitors | get $selection_index
}

def "main disable" [] {
  let selection = select_monitor
  # set to opposite of current mode
  let mode = if $selection.disabled { "enable" } else { "disable" }
  hyprctl keyword monitor $"($selection.name),($mode)"
}

def "main edit" [] {
  let selection = (
    select_monitor | select name width height refreshRate x y scale
  )
  let tempfile = (mktemp -t $"XXXXXX-($selection.name)-config.yaml")
  try {
    $selection | reject name | to yaml | save $tempfile -f
    nvim $tempfile
    let new_settings = (open $tempfile)
    print $new_settings
    let config_str = (
      $"($selection.name),($new_settings.width)x($new_settings.height)@($new_settings.refreshRate),($new_settings.x)x($new_settings.y),($new_settings.scale)"
    )
    hyprctl keyword monitor $config_str
    rm $tempfile
  } catch {|err|
    rm $tempfile
    err
  }
}

def "main reset" [] {
  hyprctl reload
}
