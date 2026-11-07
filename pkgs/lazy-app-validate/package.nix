{ writers }:
writers.writeNuBin "validate-lazy-app-config" (builtins.readFile ./lazy-app-validate.nu)
