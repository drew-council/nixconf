{
  gh-stack,
  lib,
  runCommand,
  writeScriptBin,
}:
let
  # subcommands of `gh stack`, parsed from its help output at eval time
  help = builtins.readFile (
    runCommand "gh-stack-help.txt" { } ''
      ${lib.getExe' gh-stack "gh-stack"} --help > $out
    ''
  );
  commands = lib.pipe (lib.splitString "\n" help) [
    (map (builtins.match "^  ([a-z][a-z-]*) {2,}([^ ].*[^ ])$"))
    (lib.filter (match: match != null))
    (map (match: {
      name = builtins.elemAt match 0;
      description = builtins.elemAt match 1;
    }))
  ];

  aliases = {
    a = "add";
    c = "checkout";
    i = "init";
    m = "modify";
    u = "unstack";
    v = "view";
    l = "link";
    p = "push";
    r = "rebase";
    s = "sync";
  };
  unknownAliases = lib.subtractLists (map (command: command.name) commands) (lib.attrValues aliases);
in
assert lib.assertMsg (commands != [ ]) "failed to parse subcommands from `gh-stack --help`";
assert lib.assertMsg (
  unknownAliases == [ ]
) "gs aliases point at unknown gh stack subcommands: ${lib.concatStringsSep ", " unknownAliases}";
writeScriptBin "gs" (
  builtins.replaceStrings
    [ "\"@commands@\"" "\"@aliases@\"" ]
    [
      (builtins.toJSON commands)
      (builtins.toJSON aliases)
    ]
    (builtins.readFile ./gs.nu)
)
