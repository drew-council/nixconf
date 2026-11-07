{ ... }:
{
  programs.chromium = {
    enable = true;
    commandLineArgs = [
      "--remote-debugging-port=9222"
    ];
  };
}
