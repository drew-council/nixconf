{ writeScriptBin }:
writeScriptBin "lg" (builtins.readFile ./lg.nu)
