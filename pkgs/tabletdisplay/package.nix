{ lib, writeScriptBin }:
(writeScriptBin "tabletdisplay" (builtins.readFile ./tabletdisplay.nu)).overrideAttrs (old: {
  meta = old.meta // {
    platforms = lib.platforms.linux;
  };
})
