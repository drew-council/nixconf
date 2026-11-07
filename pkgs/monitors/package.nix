{ lib, writeScriptBin }:
(writeScriptBin "monitors" (builtins.readFile ./monitors.nu)).overrideAttrs (old: {
  meta = old.meta // {
    platforms = lib.platforms.linux;
  };
})
