{ ... }:
{
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
  programs.jsonfmt.enable = true;
  programs.biome = {
    enable = true;
    includes = [
      "*.ts"
      "*.tsx"
      "*.mts"
      "*.cts"
    ];
  };
  programs.shellcheck.enable = true;
  programs.stylua.enable = true;
  programs.keep-sorted.enable = true;
  programs.ruff.enable = true;
  programs.taplo.enable = true;
  programs.gofmt.enable = true;

  programs.topiary-nushell.enable = true;
}
