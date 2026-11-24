# Overrides of packages this flake does not own. Every workaround here MUST link
# its upstream issue and state when it can be removed.
{ inputs }:

_: super: {
  tdx =
    let
      package = inputs.tdx.packages.${super.stdenv.hostPlatform.system}.default;
    in
    if super.stdenv.hostPlatform.isLinux then
      package.overrideAttrs (oldAttrs: {
        nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ super.makeWrapper ];
        postInstall = (oldAttrs.postInstall or "") + ''
          wrapProgram $out/bin/tdx \
            --prefix PATH : ${super.lib.makeBinPath [ super.wl-clipboard ]}
        '';
      })
    else
      package;
  tuicr = inputs.tuicr.packages.${super.stdenv.hostPlatform.system}.default;

  # Upstream serializes every mutation across a clone, so commands on
  # independent stacks in different worktrees cannot run at the same time:
  # https://github.com/github/gh-stack/issues/568
  # https://github.com/github/gh-stack/issues/570
  # The fork's drew/local-patches branch is the latest release plus a commit that
  # lifts that.
  # Remove it once a release closes both issues. A clone MUST NOT be used by
  # this build and an upstream one at once.
  gh-stack = inputs.gh-stack.packages.${super.stdenv.hostPlatform.system}.default;
}
