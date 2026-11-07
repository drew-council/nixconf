{ inputs, ... }:
{
  flake.modules.homeManager.terminal = {
    imports = [ inputs.nix-index-database.homeModules.default ];

    programs = {
      # enable comma for command execution direct from nix-index search
      nix-index-database.comma.enable = true;

      # Keep Bash minimal for testing.
      nix-index.enableBashIntegration = false;
    };
  };
}
