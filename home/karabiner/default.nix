{ lib, pkgs, ... }:

# Linux-style Ctrl shortcuts on macOS: a port of Karabiner-Elements' "PC-Style
# Shortcuts" rule set (Ctrl+C/V/X/Z/A/S/F/T/W/..., Ctrl+arrows, Home/End,
# ...). Terminals are excluded, so Ctrl+C still sends SIGINT in Ghostty;
# Ghostty binds Ctrl+Shift+C/V itself (tty/ghostty.nix).
#
# Upstream:
# https://github.com/pqrs-org/KE-complex_modifications/blob/main/public/json/pc_shortcuts.json
# Differences from upstream:
# - Extra modifiers never include Command, so OmniWM chords (Command+...)
#   pass through. Upstream accepts any, which turns Command+Control+L
#   (switchWorkspace.next) into Command+L in browsers.
# - Dropped "PC-Style Lock Screen" (Command+L is OmniWM's focus.right), the
#   standalone Home/End rules shadowed by "PC-Style Home/End", and the
#   PrintScreen variants shadowed by "PC-Style Screenshot".
# - Dropped "PC-Style Switch Input" (Command+Space to Control+Space), so
#   Command+Space still reaches Raycast (home/raycast.nix).
# - Helium added to the browsers.
#
# The app itself is a Homebrew cask (hosts/macos/configuration.nix).
let
  # Remote desktops and VMs: keys go to another OS, which has its own
  # shortcuts.
  remoteApps = [
    "^com\\.microsoft\\.rdc$"
    "^com\\.microsoft\\.rdc\\."
    "^net\\.sf\\.cord$"
    "^com\\.thinomenon\\.RemoteDesktopConnection$"
    "^com\\.itap-mobile\\.qmote$"
    "^com\\.nulana\\.remotixmac$"
    "^com\\.p5sys\\.jump\\.mac\\.viewer$"
    "^com\\.p5sys\\.jump\\.mac\\.viewer\\."
    "^com\\.teamviewer\\.TeamViewer$"
    "^com\\.vmware\\.horizon$"
    "^com\\.2X\\.Client\\.Mac$"
    "^com\\.OpenText\\.Exceed-TurboX-Client$"
    "^com\\.realvnc\\.vncviewer$"
    "^com\\.citrix\\.receiver\\.icaviewer"
    "^com\\.vmware\\.fusion$"
    "^com\\.vmware\\.view$"
    "^com\\.parallels\\.desktop$"
    "^com\\.parallels\\.vm$"
    "^com\\.parallels\\.desktop\\.console$"
    "^org\\.virtualbox\\.app\\.VirtualBoxVM$"
    "^com\\.citrix\\.XenAppViewer$"
    "^com\\.vmware\\.proxyApp\\."
    "^com\\.parallels\\.winapp\\."
    "^com\\.utmapp\\.UTM$"
  ];

  terminals = [
    "^com\\.apple\\.Terminal$"
    "^com\\.googlecode\\.iterm2$"
    "^co\\.zeit\\.hyperterm$"
    "^co\\.zeit\\.hyper$"
    "^io\\.alacritty$"
    "^org\\.alacritty$"
    "^net\\.kovidgoyal\\.kitty$"
    "^com\\.mitchellh\\.ghostty$"
  ];

  # Apps that use Control as Emacs-style editing keys.
  emacsApps = [
    "^org\\.gnu\\.Emacs$"
    "^org\\.gnu\\.AquamacsEmacs$"
    "^org\\.gnu\\.Aquamacs$"
    "^org\\.pqrs\\.unknownapp\\.conkeror$"
  ];

  # Apps with their own PC-style Home/End handling.
  ownHomeEnd = [
    "^cz\\.or\\.repo\\.git-gui$"
    "^com\\.jetbrains\\."
  ];

  browsers = [
    "^org\\.mozilla\\.firefox$"
    "^org\\.mozilla\\.firefoxdeveloperedition$"
    "^org\\.mozilla\\.nightly$"
    "^com\\.microsoft\\.Edge"
    "^com\\.microsoft\\.edgemac"
    "^com\\.google\\.Chrome$"
    "^com\\.brave\\.Browser$"
    "^com\\.apple\\.Safari$"
    "^net\\.imput\\.helium$"
  ];

  unless = apps: {
    type = "frontmost_application_unless";
    bundle_identifiers = apps;
  };
  onlyIn = apps: {
    type = "frontmost_application_if";
    bundle_identifiers = apps;
  };

  notRemote = unless remoteApps;
  notTerminal = unless (remoteApps ++ terminals);
  # Most rules: everywhere the Control key isn't already meaningful.
  notCtrlApp = unless (remoteApps ++ terminals ++ emacsApps);
  inBrowser = onlyIn browsers;

  # Every extra modifier except Command; see the header.
  anyButCommand = [
    "shift"
    "option"
    "fn"
    "caps_lock"
  ];

  press = key_code: modifiers: { inherit key_code modifiers; };
  run = shell_command: { inherit shell_command; };

  remap =
    {
      key,
      mandatory ? [ ],
      optional ? anyButCommand,
      to,
      conditions ? [ ],
    }:
    {
      type = "basic";
      from = {
        key_code = key;
        modifiers = { inherit mandatory optional; };
      };
      to = [ to ];
      inherit conditions;
    };

  # Control+key -> Command+key, the bulk of the rule set.
  ctrlToCmd =
    conditions: key:
    remap {
      inherit key;
      mandatory = [ "control" ];
      to = press key [ "left_command" ];
      conditions = [ conditions ];
    };

  rule = description: manipulators: { inherit description manipulators; };

  rules = [
    (rule "PC-Style Home/End" [
      (remap {
        key = "home";
        optional = [ "shift" ];
        to = press "left_arrow" [ "left_command" ];
        conditions = [ (unless (remoteApps ++ terminals ++ browsers ++ ownHomeEnd ++ emacsApps)) ];
      })
      (remap {
        key = "home";
        optional = [ "shift" ];
        to = press "a" [ "left_control" ];
        conditions = [ inBrowser ];
      })
      (remap {
        key = "home";
        mandatory = [ "control" ];
        optional = [ "shift" ];
        to = press "up_arrow" [ "left_command" ];
        conditions = [ (unless (remoteApps ++ terminals ++ ownHomeEnd ++ emacsApps)) ];
      })
      (remap {
        key = "end";
        optional = [ "shift" ];
        to = press "right_arrow" [ "left_command" ];
        conditions = [ (unless (remoteApps ++ terminals ++ browsers ++ ownHomeEnd ++ emacsApps)) ];
      })
      (remap {
        key = "end";
        optional = [ "shift" ];
        to = press "e" [ "left_control" ];
        conditions = [ inBrowser ];
      })
      (remap {
        key = "end";
        mandatory = [ "control" ];
        optional = [ "shift" ];
        to = press "down_arrow" [ "left_command" ];
        conditions = [ (unless (remoteApps ++ terminals ++ ownHomeEnd ++ emacsApps)) ];
      })
    ])
    (rule "PC-Style Copy (Ctrl+Insert) for JIS/PC keyboard" [
      (remap {
        key = "insert";
        mandatory = [ "control" ];
        to = press "c" [ "left_command" ];
      })
    ])
    (rule "PC-Style Paste (Shift+Insert) for JIS/PC keyboard" [
      (remap {
        key = "insert";
        mandatory = [ "shift" ];
        to = press "v" [ "left_command" ];
      })
    ])
    (rule "PC-Style Paste(Shift+Fn) for ANSI keyboard" [
      (remap {
        key = "fn";
        mandatory = [ "shift" ];
        to = press "v" [ "left_command" ];
      })
    ])
    (rule "Option(Alt)+Tab as Switch Application (Command+Tab)" [
      (remap {
        key = "tab";
        mandatory = [ "option" ];
        to = press "tab" [ "left_command" ];
      })
    ])
    (rule "PC-Style Control+Up/Down/Left/Right" (
      map
        (
          { key, modifier }:
          remap {
            inherit key;
            mandatory = [ "control" ];
            to = press key [ modifier ];
            conditions = [ notCtrlApp ];
          }
        )
        [
          {
            key = "left_arrow";
            modifier = "left_option";
          }
          {
            key = "right_arrow";
            modifier = "left_option";
          }
          {
            key = "up_arrow";
            modifier = "left_command";
          }
          {
            key = "down_arrow";
            modifier = "left_command";
          }
        ]
    ))
    (rule "PC-Style Copy/Paste/Cut" (
      map (ctrlToCmd notCtrlApp) [
        "c"
        "v"
        "x"
      ]
    ))
    (rule "PC-Style Undo" [ (ctrlToCmd notCtrlApp "z") ])
    (rule "PC-Style Redo" [
      (remap {
        key = "y";
        mandatory = [ "control" ];
        to = press "z" [
          "left_command"
          "left_shift"
        ];
        conditions = [ notCtrlApp ];
      })
    ])
    (rule "PC-Style Select-All" [ (ctrlToCmd notCtrlApp "a") ])
    (rule "PC-Style Save" [ (ctrlToCmd notCtrlApp "s") ])
    (rule "PC-Style New" [ (ctrlToCmd notCtrlApp "n") ])
    (rule "PC-Style Reload(F5, Ctrl+R)" [
      (ctrlToCmd notCtrlApp "r")
      (remap {
        key = "f5";
        to = press "r" [ "left_command" ];
        conditions = [ notCtrlApp ];
      })
    ])
    (rule "PC-Style New Tab" [ (ctrlToCmd notCtrlApp "t") ])
    (rule "PC-Style Find" (
      map (ctrlToCmd notCtrlApp) [
        "f"
        "g"
      ]
    ))
    (rule "PC-Style Open" [ (ctrlToCmd notCtrlApp "o") ])
    (rule "PC-Style Bold/Italic/Underline(Ctrl+B/I/U)" (
      map (ctrlToCmd notCtrlApp) [
        "b"
        "i"
        "u"
      ]
    ))
    (rule "PC-Style Close Window" [ (ctrlToCmd notCtrlApp "w") ])
    (rule "PC-Style Emoji Picker (Command+.)" [
      (remap {
        key = "period";
        mandatory = [ "command" ];
        optional = [ ];
        to = press "spacebar" [
          "left_control"
          "left_command"
        ];
        conditions = [ notRemote ];
      })
    ])
    (rule "PC-Style Spotlight Search (Command+S)" [
      (remap {
        key = "s";
        mandatory = [ "command" ];
        optional = [ ];
        to = press "spacebar" [ "left_command" ];
        conditions = [ notRemote ];
      })
    ])
    (rule "PC-Style Screenshot (PrintScreen for whole, Shift+PrintScreen to select)" [
      (remap {
        key = "print_screen";
        mandatory = [ "shift" ];
        to = press "4" [
          "left_command"
          "left_shift"
        ];
        conditions = [ notRemote ];
      })
      (remap {
        key = "print_screen";
        to = press "3" [
          "left_command"
          "left_shift"
        ];
        conditions = [ notRemote ];
      })
    ])
    (rule "PC-Style Quit Application (Alt+F4 to Command+Q)" [
      (remap {
        key = "f4";
        mandatory = [ "option" ];
        optional = [ ];
        to = press "q" [ "left_command" ];
        conditions = [ notRemote ];
      })
    ])
    (rule "Command+E Opens Finder" [
      (remap {
        key = "e";
        mandatory = [ "command" ];
        optional = [ ];
        to = run "open -a 'Finder.app'";
        conditions = [ notRemote ];
      })
    ])
    (rule "Control+Esc Opens Launchpad" [
      (remap {
        key = "escape";
        mandatory = [ "control" ];
        optional = [ ];
        to = press "launchpad" [ ];
        conditions = [ notRemote ];
      })
    ])
    (rule "Control+Shift+Esc Opens Activity Monitor" [
      (remap {
        key = "escape";
        mandatory = [
          "control"
          "shift"
        ];
        optional = [ ];
        to = run "open -a 'Activity Monitor.app'";
        conditions = [ notRemote ];
      })
    ])
    (rule "PC-Style Browser open location (Ctrl+L)" [ (ctrlToCmd inBrowser "l") ])
    (rule "PC-Style Back/Forward (Alt+Left Arrow/Alt+Right Arrow)" (
      map
        (
          key:
          remap {
            inherit key;
            mandatory = [ "option" ];
            to = press key [ "left_command" ];
            conditions = [ inBrowser ];
          }
        )
        [
          "left_arrow"
          "right_arrow"
        ]
    ))
    (rule "PC-Style Browser Zoom (Ctrl+Plus/Minus/0)" (
      map (ctrlToCmd inBrowser) [
        "hyphen"
        "keypad_hyphen"
        "equal_sign"
        "keypad_plus"
        "0"
        "keypad_0"
      ]
    ))
    (rule "PC-Style Control+Delete/Backspace" [
      (remap {
        key = "delete_or_backspace";
        mandatory = [ "control" ];
        to = press "delete_or_backspace" [ "option" ];
        conditions = [ notCtrlApp ];
      })
    ])
    (rule "PC-Style Control+Delete" [
      (remap {
        key = "delete_forward";
        mandatory = [ "control" ];
        to = press "delete_forward" [ "option" ];
        conditions = [ notTerminal ];
      })
    ])
    (rule "PC-Style Control+K" [ (ctrlToCmd notCtrlApp "k") ])
  ];

  # Wheel scrolling opposite the trackpad, replacing Scroll Reverser (whose
  # config was: vertical only, mice only, trackpad untouched). Karabiner
  # ignores pointing devices by default, so opt this one in; only its own
  # events are flipped, leaving the built-in trackpad on natural scrolling.
  # IDs from `hidutil list` (Bluetooth LE: 0x46d / 0xb034).
  mxMaster3S = {
    identifiers = {
      is_pointing_device = true;
      vendor_id = 1133;
      product_id = 45108;
    };
    ignore = false;
    mouse_flip_vertical_wheel = true;
  };

  karabinerJson = (pkgs.formats.json { }).generate "karabiner.json" {
    global.show_in_menu_bar = false;
    profiles = [
      {
        name = "Default profile";
        selected = true;
        complex_modifications.rules = rules;
        devices = [ mxMaster3S ];
        virtual_hid_keyboard.keyboard_type_v2 = "ansi";
      }
    ];
  };
in
{
  # Copy karabiner.json into a real directory rather than linking it from the
  # store. Karabiner keeps watching the store path a symlink resolved to at
  # startup, so it never sees a new generation, and it repeatedly fails to
  # chmod a read-only config directory. Edits made in the GUI are overwritten
  # on the next switch whenever this config changes, so make changes here.
  # Runs after linkGeneration, which removes the old directory symlink.
  home.activation.karabinerConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    dir="$HOME/.config/karabiner"
    if [ -L "$dir" ]; then
      run rm "$dir"
    fi
    run mkdir -p "$dir"
    if ! cmp -s ${karabinerJson} "$dir/karabiner.json"; then
      run install -m 600 ${karabinerJson} "$dir/karabiner.json"
    fi
  '';
}
