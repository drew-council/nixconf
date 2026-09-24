{ lib, ... }:

# OmniWM set up to behave like the Hyprland config in ../hyprland, with
# Command standing in for SUPER (it sits where SUPER does on the keyboard).
# Option is left entirely to herdr's alt+... bindings.
#
# OmniWM validates settings.toml strictly: every key must be present and
# `hotkeys` must list every action exactly once. defaults.toml is the file
# OmniWM 0.7.2 writes on first launch; this module only overrides values in
# it. When bumping OmniWM (overlays.nix), recapture it: move
# ~/.config/omniwm/settings.toml aside, relaunch OmniWM, and copy the fresh
# file here.
let
  defaults = lib.importTOML ./defaults.toml;

  mod = "Command";

  # OmniWM writes chords with modifiers in this order; keeping ours canonical
  # lets the collision checks below compare strings.
  chord =
    modifiers: key:
    let
      held = modifiers ++ [ mod ];
    in
    lib.concatStringsSep "+" (
      lib.filter (modifier: lib.elem modifier held) [
        "Control"
        "Option"
        "Shift"
        "Command"
      ]
      ++ [ key ]
    );

  # Catppuccin mauve -> pink, matching the Hyprland active border.
  mauve = {
    red = 0.796;
    green = 0.651;
    blue = 0.969;
    alpha = 1.0;
  };
  pink = {
    red = 0.961;
    green = 0.761;
    blue = 0.906;
    alpha = 1.0;
  };

  # Action id -> chord. Workspace 10 has no OmniWM action.
  bindings = {
    "focus.left" = chord [ ] "H";
    "focus.down" = chord [ ] "J";
    "focus.up" = chord [ ] "K";
    "focus.right" = chord [ ] "L";

    # Hyprland: SUPER+ALT.
    "resizeShrink.horizontal" = chord [ "Option" ] "H";
    "resizeGrow.vertical" = chord [ "Option" ] "J";
    "resizeShrink.vertical" = chord [ "Option" ] "K";
    "resizeGrow.horizontal" = chord [ "Option" ] "L";

    "switchWorkspace.previous" = chord [ "Control" ] "H";
    "switchWorkspace.next" = chord [ "Control" ] "L";
    "moveWindowToWorkspaceUp" = chord [ "Shift" ] "H";
    "moveWindowToWorkspaceDown" = chord [ "Shift" ] "L";

    # Hyprland: SUPER+F. Command+F is find in every app.
    "toggleFocusedWindowFloating" = chord [ "Shift" ] "F";
    "toggleFullscreen" = chord [ "Shift" ] "M";
    "closeFocusedWindow" = chord [ "Shift" ] "W";
  }
  // lib.listToAttrs (
    lib.concatMap (
      index:
      let
        key = toString (index + 1);
      in
      [
        (lib.nameValuePair "switchWorkspace.${toString index}" (chord [ ] key))
        (lib.nameValuePair "moveToWorkspace.${toString index}" (chord [ "Shift" ] key))
      ]
    ) (lib.range 0 8)
  );

  actionIds = map (hotkey: hotkey.id) defaults.hotkeys;
  unknownActions = lib.subtractLists actionIds (lib.attrNames bindings);
  claimed = lib.attrValues bindings;

  # Unassign every other default that collides with ours or uses Option,
  # which belongs to herdr.
  hotkeys = map (
    hotkey:
    if bindings ? ${hotkey.id} then
      hotkey // { binding = bindings.${hotkey.id}; }
    else if lib.elem hotkey.binding claimed || lib.hasInfix "Option" hotkey.binding then
      hotkey // { binding = "Unassigned"; }
    else
      hotkey
  ) defaults.hotkeys;

  assigned = lib.filter (binding: binding != "Unassigned") (map (hotkey: hotkey.binding) hotkeys);
  duplicateBindings = lib.unique (
    lib.filter (binding: lib.count (other: other == binding) assigned > 1) assigned
  );

  overrides = {
    general = {
      defaultLayoutType = "dwindle";
      # The version is pinned through Nix.
      updateChecksEnabled = false;
      # For omniwmctl.
      ipcEnabled = true;
    };

    # Hyprland: follow_mouse = 1.
    focus.followsMouse = true;

    # Hyprland: gaps_in = 5 (per side), gaps_out = 10. outer.top is measured
    # from the top of the display with the menu bar subtracted, so it
    # includes the 24pt menu bar.
    gaps = {
      size = 10.0;
      outer = {
        left = 10.0;
        right = 10.0;
        top = 34.0;
        bottom = 10.0;
      };
    };

    borders = {
      width = 2.0;
      color = mauve;
      gradient = {
        enabled = true;
        direction = "topLeftToBottomRight";
        start = mauve;
        end = pink;
      };
    };

    gestures = {
      # Column scrolling is Niri-only, and its three-finger swipe would clash
      # with the workspace swipe.
      scrollEnabled = false;
      # Hyprland: three-finger horizontal swipe switches workspace. The
      # matching macOS gesture is turned off in hosts/macos/configuration.nix.
      workspaceSwipeEnabled = true;
      workspaceSwipeFingerCount = 3;
      workspaceSwipeAxis = "horizontal";
      # SUPER + left drag moves, SUPER + right drag resizes.
      mouseMoveModifierKey = "command";
      mouseResizeModifierKey = "command";
    };
  };
in
{
  assertions = [
    {
      assertion = unknownActions == [ ];
      message = "OmniWM bindings reference unknown actions: ${lib.concatStringsSep ", " unknownActions}";
    }
    {
      assertion = duplicateBindings == [ ];
      message = "OmniWM chords bound more than once: ${lib.concatStringsSep ", " duplicateBindings}";
    }
  ];

  programs.omniwm = {
    enable = true;
    settings = lib.recursiveUpdate defaults overrides // {
      inherit hotkeys;
      workspaces = map (
        workspace:
        removeAttrs workspace [ "displayName" ]
        // {
          layoutType = "default";
        }
      ) defaults.workspaces;
    };
  };
}
