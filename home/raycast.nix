{
  config,
  lib,
  pkgs,
  ...
}:

# Raycast replaces Spotlight on Command+Space. The app itself comes from
# nixpkgs, with a login item below. Home Manager has no Raycast module, and
# Raycast 2.x keeps all of its settings, the global hotkey included, in an
# encrypted database (settings_v2.db), not in com.raycast.macos defaults. Set
# the hotkey once in Settings > General > Raycast Hotkey; use Settings >
# Advanced > Export to back up the rest.
let
  app = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Raycast.app";
in
{
  home.packages = [ pkgs.raycast ];

  # Raycast silently self-updates whenever its bundle is user-writable, and
  # copyApps leaves it writable. The next activation copies the nixpkgs bundle
  # back, and the older version can't open the database the newer one
  # migrated, so it resets it. A read-only bundle dir makes the updater need a
  # privileged helper that is never approved here, so it only offers the
  # update in the UI. Decline it; updates come from nixpkgs.
  home.activation.unlockRaycastBundle =
    lib.hm.dag.entryBefore [ "checkAppManagementPermission" "copyApps" ]
      ''
        if [[ -d ${lib.escapeShellArg app} ]]; then
          run /bin/chmod u+w ${lib.escapeShellArg app}
        fi
      '';
  home.activation.lockRaycastBundle = lib.hm.dag.entryAfter [ "copyApps" ] ''
    run /bin/chmod a-w ${lib.escapeShellArg app}
  '';

  # Raycast 2.9+ also honors this as an update policy; 2.7 ignores it.
  targets.darwin.defaults."com.raycast.macos".DisableAutomaticUpdates = true;

  # Login item: RunAtLoad fires the agent on every login, and `open -na`
  # launches the copyApps copy (so LaunchServices sees the real bundle) and
  # returns immediately. ProgramArguments only, as in programs/voxtype.nix.
  launchd.agents.raycast = {
    enable = true;
    config = {
      ProgramArguments = [
        "/usr/bin/open"
        "-na"
        app
      ];
      RunAtLoad = true;
    };
  };

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
