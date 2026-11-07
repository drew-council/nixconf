{
  flake.modules.homeManager.desktop-linux =
    { config, ... }:
    {
      # spotify TUI player
      programs.spotify-player = {
        enable = true;
        settings = {
          # fetch the client ID using 1Password
          client_id_command = {
            command = "op";
            args = [
              "--account"
              "L23KMYOBNVHLPGSIPDX7BAQ5LA"
              "read"
              "op://opnix/spotify-player/credential"
            ];
          };

          device = {
            name = "${config.my.host.name}-spotify-player";
            volume = 85;
            type = "computer";
            normalization = true;
          };

          # weird values needed to make album art square
          cover_img_width = 9;
          cover_img_length = 20;

          border_type = "Rounded";
          layout = {
            playback_window_position = "Bottom";
            playback_window_height = 10;
          };
        };
        actions = [
          {
            action = "ToggleLiked";
            key_sequence = "C-l";
          }
          {
            action = "AddToLibrary";
            key_sequence = "C-a";
          }
          {
            action = "Follow";
            key_sequence = "C-f";
          }
        ];
        keymaps = [
          {
            command = "PreviousPage";
            key_sequence = "esc";
          }
          {
            command = "ClosePopup";
            key_sequence = "q";
          }
          {
            command = "Repeat";
            key_sequence = "R";
          }
          {
            command = "Shuffle";
            key_sequence = "S";
          }
          {
            command = "Quit";
            key_sequence = "C-c";
          }
          {
            command = {
              SeekForward = {
                duration = 5;
              };
            };
            key_sequence = "L";
          }
          {
            command = {
              SeekBackward = {
                duration = 5;
              };
            };
            key_sequence = "H";
          }
          {
            command = "PageSelectPreviousOrScrollUp";
            key_sequence = "C-u";
          }
          {
            command = "PageSelectNextOrScrollDown";
            key_sequence = "C-d";
          }
          {
            command = "LikedTrackPage";
            key_sequence = "g o";
          }
        ];
      };

      # create desktop shortcut for launching
      xdg.desktopEntries.spotify-player = {
        name = "spotify-player";
        exec = "ghostty -e spotify_player";
        terminal = false;
        type = "Application";
        categories = [
          "Audio"
          "AudioVideo"
          "Music"
        ];
      };
    };
}
