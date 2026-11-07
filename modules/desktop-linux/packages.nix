{ inputs, ... }:
{
  flake.modules.nixos.desktop-linux =
    { lib, pkgs, ... }:
    let
      icat = pkgs.writeShellScriptBin "icat" ''
        exec ${lib.getExe pkgs.kitty} +kitten icat "$@"
      '';

      # nixpkgs exposes Zed as `zeditor`; add the expected `zed` binary to PATH.
      zed = pkgs.symlinkJoin {
        name = "zed";
        paths = [ pkgs.zed-editor ];
        meta = pkgs.zed-editor.meta // {
          mainProgram = "zed";
        };
        postBuild = ''
          ln -s "$out/bin/zeditor" "$out/bin/zed"
        '';
      };
    in
    {
      environment.systemPackages = with pkgs; [
        # file managers
        kdePackages.dolphin
        lxqt.pcmanfm-qt

        thunderbird # email
        libreoffice-qt-stable # office suite
        kdePackages.okular # pdf viewer
        system-config-printer

        # browsers
        inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.helium-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
        google-chrome
        agent-browser # browser automation CLI for AI agents
        # firefox in home manager

        qalculate-qt # calculator

        pcloud # cloud storage
        localsend # local file sharing between devices
        wireshark # packet monitoring

        libnotify # notification library setup
        gparted # partition editor

        audacity # audio editor
        gimp # raster editor
        inkscape # vector editor
        feh # image viewer
        ksnip # image annotation
        prusa-slicer # slicer for 3D printing

        vlc
        mpv # preferred media playback
        kdePackages.kdenlive

        spotify
        ytmdesktop # desktop app for youtube music
        calibre
        pdfarranger

        # code editors
        zed-editor # preferred code editor
        zed # alias
        vscodium

        alacritty
        ghostty
        kitty
        icat

        kdePackages.qtwayland
        kdePackages.qtsvg
        kdePackages.qt6ct
        kdePackages.kio-fuse
        kdePackages.kio-extras
        kdePackages.plasma-workspace
        kdePackages.kconfig

        libva-utils # utilities to check vaapi stuff
        vulkan-tools # tools for testing vulkan
        mesa-demos # graphics demos for testing GPU
        pulseaudio # utilities for pulseaudio control, works against wireplumber emulated pulseaudio

        qbittorrent

        logseq # markdown note-taking

        signal-desktop
      ];

      # fix dolphin default programs
      # https://discourse.nixos.org/t/dolphin-does-not-have-mime-associations/48985/8
      environment.etc."/xdg/menus/applications.menu".text =
        builtins.readFile "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";
    };
}
