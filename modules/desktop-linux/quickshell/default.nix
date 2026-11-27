{
  flake.modules.homeManager.desktop-linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      tailscaleStatus = pkgs.writeShellApplication {
        name = "bar-tailscale-status";
        runtimeInputs = [
          pkgs.jq
          pkgs.tailscale
        ];
        text = ''
          status="$(tailscale status --json 2>/dev/null)" || exit 0

          if [[ "$(jq -r '.BackendState == "Running" and .Self.Online' <<< "$status")" != "true" ]]; then
            exit 0
          fi

          jq -c '
            {
              tooltip: (
                "Tailscale connected\n" +
                (.Self.DNSName // .Self.HostName) + "\n" +
                "IP: " + ((.TailscaleIPs | map(select(contains(":") | not)) | first) // "unknown") + "\n" +
                "Online peers: " + ([ (.Peer // {})[] | select(.Online) ] | length | tostring)
              )
            }
          ' <<< "$status"
        '';
      };

      bar = pkgs.runCommand "quickshell-bar" { } ''
        cp -r ${./bar} $out
        chmod -R u+w $out
        substituteInPlace $out/Tailscale.qml \
          --replace-fail "@tailscaleStatus@" "${lib.getExe tailscaleStatus}"
        substituteInPlace $out/EmojiProvider.qml \
          --replace-fail "@emojiTest@" "${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt" \
          --replace-fail "@wtype@" "${lib.getExe pkgs.wtype}"
        substituteInPlace $out/Dictation.qml \
          --replace-fail "@voxtype@" "${lib.optionalString config.services.voxtype.enable (lib.getExe config.services.voxtype.package)}"
      '';
    in
    {
      programs.quickshell = {
        enable = true;
        configs.bar = bar;
      };
    };
}
