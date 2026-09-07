{
  pkgs,
  lib,
  config,
  inputs,
  vars,
  ...
}:
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
  imports = [
    ./1password-gui.nix
    ./flatpak.nix
    ./fonts.nix
    ./kwallet.nix
    ./pwa.nix
    ./spacemouse.nix
    ./virtmanager.nix
  ];

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  environment.systemPackages =
    with pkgs;
    (
      [
        # file managers
        kdePackages.dolphin
        lxqt.pcmanfm-qt

        thunderbird # email
        libreoffice-qt6-fresh # office suite
        # marktext # markdown wysiwyg editor
        kdePackages.okular # pdf viewer
        system-config-printer

        # browsers
        inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
        google-chrome
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
        # calibre
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

        libva-utils # utilites to check vaapi stuff
        vulkan-tools # tools for testing vulkan
        mesa-demos # grahphics demos for testing GPU
        pulseaudio # utilities for pulseaudio control, works against wireplumber emulated pulseaudio

        hidapi # needed for steam controller
      ]
      ++ (
        if (vars.isPersonal config) then
          [
            qbittorrent

            logseq # markdown note-taking

            # jellyfin-mpv-shim

            signal-desktop
            # element-desktop currently pulls in the insecure jitsi-meet-1.0.8792 package causing nix evaluation failures.
            # element-desktop

            apotris
            prismlauncher

            # emulation
            mame
            mame-tools
            dolphin-emu
            (retroarch.withCores (
              # specify retroarch cores to include
              cores: with cores; [
                # snes
                snes9x
                # gba
                mgba
                # nes
                mesen
                # psx
                beetle-psx-hw
              ]
            ))
          ]
        else
          [ ]
      )
    );

  # fix dolphin default programs
  # https://discourse.nixos.org/t/dolphin-does-not-have-mime-associations/48985/8
  environment.etc."/xdg/menus/applications.menu".text =
    builtins.readFile "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

  programs = {
    steam = lib.mkIf (vars.isPersonal config) {
      enable = true;
      extest.enable = true;
      extraPackages = with pkgs; [
        hidapi
        python3Packages.hidapi
      ];
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
    };

    weylus = {
      enable = false;
      openFirewall = true;
      users = [ vars.user ];
    };

  };

  services = {
    mullvad-vpn = lib.mkIf (vars.isPersonal config) {
      enable = true;
      gui.enable = true;
    };

    # web ui for ollama and similar
    open-webui = {
      enable = false;
      port = 31743;
    };

    desktopManager.plasma6.enableQt5Integration = true;
  };

  # autostart steam in background
  systemd.user.services.steam = lib.mkIf (vars.isPersonal config) {
    enable = true;
    description = "Open Steam in the background at boot";
    serviceConfig = {
      ExecStart = "${lib.getExe config.programs.steam.package} -nochatui -nofriendsui -silent %U";
      wantedBy = [ "graphical-session.target" ];
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # waydroid - android emulation
  virtualisation.waydroid = lib.mkIf (vars.isPersonal config) {
    enable = true;
  };

  catppuccin = {
    enable = true;
    autoEnable = true;
  };

  qt = {
    enable = true;
    platformTheme = "qt5ct";
    style = "kvantum";
  };
}
