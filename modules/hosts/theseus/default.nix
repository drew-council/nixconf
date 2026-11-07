let
  scaleHiDPI = 1.5;
in
{
  hosts.theseus = {
    system = "x86_64-linux";

    features = [
      "base"
      "home-lan"
      "terminal"
      "desktop"
      "desktop-linux"
      "gaming"
      "laptop"
      "work"
    ];

    display = {
      monitors = {
        laptop = {
          desc = "BOE 0x095F";
          settings = {
            mode = "preferred";
            position = "auto-down";
            scale = 1.566667;
          };
        };
      };

      profiles = {
        "1080p" = {
          enabledOutputs = [ "laptop" ];
          useTablet = false;
          monitorOverrides = {
            laptop = {
              mode = "1920x1080";
              scale = scaleHiDPI;
            };
          };
        };
        tablet = {
          enabledOutputs = [ "laptop" ];
          useTablet = true;
        };
      };
    };

    module =
      { pkgs, ... }:
      {
        imports = [ ./_hardware.nix ];

        # Alder Lake-P iGPU (46a6) should use i915 on this host.
        # xe currently probes first on linuxPackages_latest but is unsupported here,
        # which causes userspace to fall back to llvmpipe software rendering.
        boot.kernelParams = [
          "xe.force_probe=!46a6"
          "i915.force_probe=46a6"
        ];

        services.fwupd.enable = true;

        # Keep encrypted SSDs fast under Docker/build churn: pass TRIM and skip dm-crypt queues.
        boot.initrd.luks.devices."luks-2bf7370e-9689-4cf5-908b-f409a55ae9ce" = {
          allowDiscards = true;
          bypassWorkqueues = true;
        };

        hardware.graphics.extraPackages = with pkgs; [
          intel-media-driver # For Broadwell (2014) or newer processors. LIBVA_DRIVER_NAME=iHD
        ];

        system.stateVersion = "24.11";
      };
  };
}
