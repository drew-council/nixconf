# Everything an NVIDIA host needs. No current host lists this feature.
{
  flake.modules.nixos.nvidia =
    {
      config,
      lib,
      pkgs,
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
          '';
        }
      );
    in
    {
      environment.systemPackages = with pkgs; [
        egl-wayland # EGL external platform for Wayland
        nvitop # GPU process viewer
        nvidia-container-toolkit # GPU access from containers
      ];

      boot.kernelParams = [
        "nvidia-drm.modeset=1"
        "nvidia-drm.fbdev=1"
      ];

      hardware.nvidia = {
        # Modesetting is required.
        modesetting.enable = true;

        # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
        # Enable this if you have graphical corruption issues or application crashes after waking
        # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
        # of just the bare essentials.
        powerManagement.enable = false;

        # Fine-grained power management. Turns off GPU when not in use.
        # Experimental and only works on modern Nvidia GPUs (Turing or newer).
        powerManagement.finegrained = false;

        # Use the NVidia open source kernel module (not to be confused with the
        # independent third-party "nouveau" open source driver).
        # Support is limited to the Turing and later architectures. Full list of
        # supported GPUs is at:
        # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
        # Only available from driver 515.43.04+
        open = false;

        # Enable the Nvidia settings menu,
        # accessible via `nvidia-settings`.
        nvidiaSettings = true;

        # Optionally, you may need to select the appropriate driver version for your specific GPU.
        package = config.boot.kernelPackages.nvidiaPackages.latest;
      };

      # enable nvidia hardware toolkit for docker integration
      hardware.nvidia-container-toolkit.enable = true;

      programs._1password-gui.package = x11-1password-gui;

      services.xserver.videoDrivers = [ "nvidia" ];
    };

  flake.modules.homeManager.nvidia.programs.chromium.commandLineArgs = [
    "--ozone-platform-hint=x11"
  ];
}
