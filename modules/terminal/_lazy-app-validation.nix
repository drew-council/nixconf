{
  lib,
  pkgs,
}:
{
  arguments ? [ ],
  displayName,
  expectedFailure,
  package,
  program,
  settings,
}:
let
  configFile = (pkgs.formats.yaml { }).generate "${program}-config-validation.yml" settings;
  executable = lib.getExe package;
in
lib.hm.dag.entryBefore [ "writeBoundary" ] ''
  run ${lib.getExe pkgs.lazy-app-validate} ${
    lib.escapeShellArgs (
      [
        displayName
        "programs.${program}.settings"
        configFile
        executable
        (lib.getExe' pkgs.util-linux "setsid")
        expectedFailure
      ]
      ++ arguments
    )
  }
''
