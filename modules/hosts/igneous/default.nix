let
  scaleHiDPI = 1.5;
in
{
  hosts.igneous = {
    system = "x86_64-linux";

    features = [
      "base"
      "home-lan"
      "terminal"
      "desktop"
      "desktop-linux"
      "gaming"
      "game-mode"
      "work"
    ];

    display = {
      defaultAudioOutputAlsaName = "USB Audio";
      # Profile whose audio settings game mode uses.
      gameModeProfile = "tv";

      gameMode = {
        connector = "HDMI-A-1";
        vkDevice = "1002:744c"; # RX 7900 XTX; the iGPU is 1002:164e
      };

      monitors = {
        main = {
          desc = "Microstep MSI MAG322UPF";
          settings = {
            mode = "3840x2160@160";
            position = "0x0";
            scale = scaleHiDPI;
            vrr = 0;
          };
        };
        top = {
          desc = "ViewSonic Corporation VX2418-P FHD WFK231321682";
          settings = {
            mode = "1920x1080@60";
            position = "575x-1080";
            scale = 1.0;
          };
        };
        kvm = {
          desc = "GLI GLKVM 891247";
          settings = {
            mode = "1920x1080@60";
            position = "auto-left";
            scale = 1.0;
          };
        };
        tv = {
          desc = "LG Electronics LG TV SSCR2 0x01010101";
          settings = {
            mode = "3840x2160@120";
            position = "auto-right";
            scale = scaleHiDPI;
          };
        };
      };

      profiles = {
        dnd = {
          enabledOutputs = [ "tv" ];
          useTablet = true;
        };
        tv = {
          audioCardName = "alsa_card.pci-0000_03_00.1";
          audioCardProfile = "output:hdmi-stereo-extra3";
          defaultAudioOutputAlsaName = "HDMI 3";
          enabledOutputs = [ "tv" ];
          useTablet = false;
        };
        kvm = {
          enabledOutputs = [ "kvm" ];
          useTablet = false;
        };
        desktop = {
          enabledOutputs = [
            "main"
            "top"
          ];
          useTablet = false;
        };
      };
    };

    module =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        imports = [
          ./_hardware.nix
          ./_agent-artifacts-proxy.nix
          ./_archipelago
        ];

        boot = {
          kernelParams = [ "amdgpu.dcfeaturemask=0x400" ];
          # start amd driver at boot
          initrd.kernelModules = [ "amdgpu" ];
          # enable kernel for disc drive
          kernelModules = [ "sg" ];
          # support ntfs for mounting windows partition
          supportedFilesystems = [ "ntfs" ];
        };

        environment.systemPackages = with pkgs; [
          lumafly
        ];

        # Homarr system health and resource monitoring. The web UI is disabled;
        # Homarr only needs the Glances v4 API on the LAN.
        services.glances = {
          enable = true;
          # python-jose is insecure and only backs optional JWT auth, which
          # glances disables when the module is absent.
          package = pkgs.glances.overridePythonAttrs (old: {
            # Match by pname: comparing derivations forces the insecure check.
            dependencies = builtins.filter (p: (p.pname or "") != "python-jose") old.dependencies;
          });
          openFirewall = true;
          extraArgs = [
            "--webserver"
            "--disable-webui"
          ];
        };

        networking.firewall = {
          enable = lib.mkForce true;
          allowedTCPPorts = [
            41707 # pi remote-control
          ];
        };

        users.users.${config.my.user.name}.openssh.authorizedKeys.keys = [
          config.my.user.sshPublicKey
        ];

        fileSystems = {
          # mount windows partition
          "/mnt/windows" = {
            device = "/dev/disk/by-uuid/5E06928506925DB9";
            fsType = "ntfs";
            options = [
              "rw"
              "uid=1000"
              "gid=100"
            ];
          };

          # mount storage drive
          "/mnt/storage" = {
            device = "/dev/disk/by-uuid/552ef407-76b5-4ce3-84cc-9c278eda76c2";
            fsType = "xfs";
            options = [
              "noatime"
              "nofail"
            ];
          };
        };

        system.stateVersion = "24.11";
      };
  };
}
