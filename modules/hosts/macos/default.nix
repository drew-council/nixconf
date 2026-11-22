{
  hosts.macos = {
    system = "aarch64-darwin";

    features = [
      "base"
      "terminal"
      "desktop"
      "desktop-macos"
      "voxtype"
      "work"
    ];

    module.system.stateVersion = 7;
  };
}
