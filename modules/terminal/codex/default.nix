# Codex reads /etc/codex/config.toml as a layer below ~/.codex/config.toml.
# The settings authored here live in that system layer.
# ~/.codex/config.toml stays unmanaged and holds what Codex writes itself:
# project trust entries, hook hashes, notices, and MCP servers with credentials.
# A key set in the user file shadows the same key here.
{
  flake.modules =
    let
      module =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          settings = lib.recursiveUpdate (lib.importTOML ./config.toml) {
            sandbox_workspace_write.writable_roots = map (dir: "${config.my.user.home}/${dir}") [
              ".cache"
              ".local"
              ".cargo"
              "go"
            ];
          };
        in
        {
          environment.etc."codex/config.toml".source =
            (pkgs.formats.toml { }).generate "codex-config.toml"
              settings;
        };
    in
    {
      nixos.terminal = module;
      darwin.terminal = module;
    };
}
