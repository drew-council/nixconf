{
  pkgs,
  lib,
  vars,
  ...
}:
let
  # import all files in the ./src directory as scripts
  scriptDir = ./src;
  scriptFileNames = builtins.attrNames (builtins.readDir scriptDir);
  linuxOnlyScripts = [
    "monitors.nu"
    "tabletdisplay.nu"
  ];
  enabledScripts = lib.filter (
    filename: pkgs.stdenv.hostPlatform.isLinux || !(builtins.elem filename linuxOnlyScripts)
  ) scriptFileNames;

  # make a script with binary name based on script name
  getName = filename: builtins.elemAt (lib.splitString "." filename) 0;
  getPath = filename: scriptDir + "/${filename}";
  # Scripts can reference vars via @token@ placeholders, e.g. @workDir@.
  substitutions = {
    "@workDir@" = vars.workDir;
  };
  substitute =
    text:
    lib.replaceStrings (builtins.attrNames substitutions) (builtins.attrValues substitutions) text;
  makeScript =
    filename:
    pkgs.writeScriptBin (getName filename) (substitute (builtins.readFile (getPath filename)));
in
{
  home.packages = map makeScript enabledScripts;
}
