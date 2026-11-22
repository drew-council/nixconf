# Secrets are age files in ../../secrets, declared with `age.secrets` in the
# Home Manager module that uses them and decrypted by a user service.
# The identity is the passphrase-less machine key from ./git.nix,
# so activation never needs 1Password or the network.
{ inputs, ... }:
{
  flake.modules.homeManager.terminal =
    { config, pkgs, ... }:
    let
      inherit (import ./_vcs-settings.nix { inherit config pkgs; }) machineKey;
      agenix = inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in
    {
      imports = [ inputs.agenix.homeManagerModules.default ];

      age.identityPaths = [ machineKey ];

      home.packages = [ agenix ];
      # The CLI only tries ~/.ssh/id_ed25519 and id_rsa by default.
      home.shellAliases.agenix = "agenix -i ${machineKey}";
    };
}
