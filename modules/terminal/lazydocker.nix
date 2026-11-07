{
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      mkLazyAppConfigValidation = import ./_lazy-app-validation.nix { inherit lib pkgs; };
    in
    {
      programs.lazydocker = {
        enable = true;
        settings.gui = {
          returnImmediately = true;
        };
      };

      home.activation.validateLazydockerConfig =
        lib.mkIf pkgs.stdenv.hostPlatform.isLinux
          (mkLazyAppConfigValidation {
            displayName = "Lazydocker";
            expectedFailure = "terminal not cursor addressable";
            package = config.programs.lazydocker.package;
            program = "lazydocker";
            settings = config.programs.lazydocker.settings;
          });
    };
}
