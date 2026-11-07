{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        apotris # block stacking game
        prismlauncher # Minecraft launcher

        # emulation
        mame # arcade emulator
        mame-tools # disk image tools for MAME
        dolphin-emu # GameCube and Wii emulator
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

        hidapi # needed for steam controller
      ];

      programs.steam = {
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
    };
}
