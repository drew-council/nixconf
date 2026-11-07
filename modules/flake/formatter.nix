{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      treefmt = inputs.treefmt-nix.lib.evalModule pkgs {
        imports = [ inputs.topiary-nushell.treefmtModules.default ];

        projectRootFile = "flake.nix";
        programs = {
          biome = {
            enable = true;
            includes = [
              "*.ts"
              "*.tsx"
              "*.mts"
              "*.cts"
            ];
          };
          gofmt.enable = true;
          jsonfmt.enable = true;
          keep-sorted.enable = true;
          nixfmt.enable = true;
          ruff.enable = true;
          shellcheck.enable = true;
          stylua.enable = true;
          taplo.enable = true;
          topiary-nushell.enable = true;
        };
      };
    in
    {
      formatter = treefmt.config.build.wrapper;
      checks.formatting = treefmt.config.build.check inputs.self;
    };
}
