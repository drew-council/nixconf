{ inputs, ... }:
{
  flake.modules.homeManager.work =
    { lib, pkgs, ... }:
    let
      antigravity-cli = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli;

      # Signs the terminal UI in to Sheer's Vertex AI project with gcloud ADC.
      # Set here rather than as session variables so other Google SDK clients keep their own project.
      # T3 Code runs `agy acp` and passes its own credentials.
      agy = pkgs.writeShellScriptBin "agy" ''
        export AGY_CLI_DISABLE_AUTO_UPDATE=1
        if [[ "''${1-}" != acp ]]; then
          export AGY_ADC_AUTH=true
          export GOOGLE_CLOUD_QUOTA_PROJECT=optimum-nebula-375615
        fi
        exec ${lib.getExe antigravity-cli} "$@"
      '';
    in
    {
      home.packages = [ agy ];
    };
}
