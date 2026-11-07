{ config, ... }:
let
  inherit (config.my) liveLink;

  liveScripts = [
    # keep-sorted start
    "canopy-local"
    "dockerkillall"
    "flakeup"
    "ma"
    "mergequeue"
    "mnix"
    "prunegit"
    "reviewprs"
    "self-resolve"
    "sheer-release"
    "worktree-cleanup"
    # keep-sorted end
  ];

  scriptPath = name: ./scripts + "/${name}.nu";
in
{
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.packages =
        map (name: pkgs.writeScriptBin name (builtins.readFile (scriptPath name))) liveScripts
        ++ [
          pkgs.lg
          pkgs.register-git-key
        ];

      # Shadows the baseline on PATH, so edits apply without a rebuild.
      home.file = lib.listToAttrs (
        map (
          name: lib.nameValuePair ".local/bin/${name}" { source = liveLink config (scriptPath name); }
        ) liveScripts
      );
    };
}
