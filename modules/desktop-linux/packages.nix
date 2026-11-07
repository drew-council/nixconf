{
  flake.modules.nixos.desktop-linux =
    { pkgs, ... }:
    let
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
        lxqt.pcmanfm-qt # lightweight file manager

        thunderbird # email
        libreoffice-qt-stable # office suite
        kdePackages.okular # pdf viewer

        qalculate-qt # calculator

        pcloud # cloud storage
        localsend # local file sharing between devices
        wireshark # packet monitoring

        gparted # partition editor

        audacity # audio editor
        gimp # raster editor
        inkscape # vector editor
        ksnip # image annotation
        prusa-slicer # slicer for 3D printing

        vlc # media player
        mpv # preferred media playback
        kdePackages.kdenlive # video editor

        spotify # music streaming
        ytmdesktop # desktop app for youtube music
        calibre # ebook library manager
        pdfarranger # merge and rearrange pdf pages

        # code editors
        zed-editor # preferred code editor
        zed # alias
        vscodium # vscode without telemetry

        kdePackages.qtwayland # Qt Wayland platform plugin
        kdePackages.qtsvg # Qt SVG support
        kdePackages.qt6ct # Qt 6 theme settings
        kdePackages.kio-fuse # exposes KIO locations to non-KDE apps
        kdePackages.kio-extras # extra KIO protocols and thumbnails
        kdePackages.plasma-workspace # Plasma libraries and menu definitions
        kdePackages.kconfig # KDE configuration tools

        libva-utils # utilities to check vaapi stuff
        vulkan-tools # tools for testing vulkan
        mesa-demos # graphics demos for testing GPU
        pulseaudio # utilities for pulseaudio control, works against wireplumber emulated pulseaudio

        qbittorrent # torrent client

        logseq # markdown note-taking

        signal-desktop # signal messenger
      ];
    };
}
