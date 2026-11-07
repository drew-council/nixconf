{ writeScriptBin }:
writeScriptBin "register-git-key" (builtins.readFile ./register-git-key.nu)
