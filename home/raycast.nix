{ lib, ... }:

# Raycast replaces Spotlight on Command+Space. The app itself comes from
# nixpkgs, with a login item (hosts/macos/configuration.nix). Home Manager has
# no Raycast module, and Raycast 2.x keeps all of its settings, the global
# hotkey included, in an encrypted database (settings_v2.db), not in
# com.raycast.macos defaults. Set the hotkey once in Settings > General >
# Raycast Hotkey; use Settings > Advanced > Export to back up the rest.
{
  # Free Command+Space for Raycast by disabling Spotlight's "Show Spotlight
  # search" shortcut (symbolic hotkey 64; parameters are char code, keycode,
  # and Command's modifier mask). -dict-add merges this one entry, where
  # targets.darwin.defaults would replace the whole AppleSymbolicHotKeys
  # dictionary and reset every other system shortcut. activateSettings applies
  # the change without logging out.
  home.activation.disableSpotlightHotkey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 '<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>'
    run /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
