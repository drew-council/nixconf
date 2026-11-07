{ inputs, ... }:
{
  flake.modules.homeManager.terminal = {
    imports = [ inputs.agent-artifacts.homeManagerModules.default ];
    services.agent-artifacts.enable = true;
  };
}
