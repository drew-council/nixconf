let
  scaleHiDPI = 1.5;

  # Primary edit surface: define monitor/profile intent per host here.
  hosts = {
    igneous = {
      defaultAudioOutputAlsaName = "USB Audio";

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

    theseus = {
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
  };

  tabletHeadless = {
    name = "HEADLESS-TABLET";
    width = 2560;
    height = 1600;
    downsample = 2;
    scale = 1.0;
    position = "auto-left";
  };
in
{
  inherit
    hosts
    tabletHeadless
    ;
}
