{ inputs, ... }:
{
  imports = [ inputs.agent-artifacts.homeManagerModules.default ];
  services.agent-artifacts = {
    enable = true;
    # The skill is registered by the Pi repo, independently of HM activation.
    installPiSkill = false;
  };
}
