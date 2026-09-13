{
  lib,
  pkgs,
  config,
  vars,
  ...
}:
let
  # version of 1password set to use x11 instead of wayland
  # needed for nvidia to be able to pop up password prompt from CLI integration
  x11-1password-gui = pkgs._1password-gui.overrideAttrs (
    finalAttrs: previousAttrs: {
      preFixup = ''
        # makeWrapper defaults to makeBinaryWrapper due to wrapGAppsHook
        # but we need a shell wrapper specifically for `NIXOS_OZONE_WL`.
        # Electron is trying to open udev via dlopen()
        # and for some reason that doesn't seem to be impacted from the rpath.
        # Adding udev to LD_LIBRARY_PATH fixes that.
        # Make xdg-open overrideable at runtime.
        makeShellWrapper $out/share/1password/1password $out/bin/1password \
          "''${gappsWrapperArgs[@]}" \
          --suffix PATH : ${lib.makeBinPath [ pkgs.xdg-utils ]} \
          --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.udev ]}
          # Currently half broken on wayland (e.g. no copy functionality)
          # See: https://github.com/NixOS/nixpkgs/pull/232718#issuecomment-1582123406
          # Remove this comment when upstream fixes:
          # https://1password.community/discussion/comment/624011/#Comment_624011
          #--add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
      '';
    }
  );
in
{
  programs._1password-gui = {
    enable = true;
    # use x11 package override if using nvidia
    package = if config.nvidiaEnable then x11-1password-gui else pkgs._1password-gui;
    # Certain features, including CLI integration and system authentication support,
    # require enabling PolKit integration on some desktop environments (e.g. Plasma).
    polkitPolicyOwners = [ vars.user ];
  };

  # set 1password to trust zen and helium to integrate with browser extension
  environment.etc = {
    "1password/custom_allowed_browsers" = {
      text = ''
        zen
        .zen-wrapped
        helium
        helium-wrapper
      '';
      mode = "0755";
    };
  };

}
