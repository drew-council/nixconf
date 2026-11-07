{
  hosts.macos = {
    system = "aarch64-darwin";

    features = [
      "base"
      "terminal"
      "desktop"
      "desktop-macos"
      "work"
    ];

    module.system.stateVersion = 7;
  };
}
