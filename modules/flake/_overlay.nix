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
  # The fork's drew/local-patches branch is the 0.3.0 release plus a commit that
  # lifts that.
  # Remove it once a release closes both issues. A clone MUST NOT be used by
  # this build and an upstream one at once.
  gh-stack = super.gh-stack.overrideAttrs (_: {
    version = "0.3.0-unstable-2026-11-24";
    src = super.fetchFromGitHub {
      owner = "drew-council";
      repo = "gh-stack";
      rev = "314ea27eb0ac92ab7598fdae3e4293eef7d7c86f";
      hash = "sha256-GMqKdLSmmcVXnwXWIJnGCbazhGhHeIzk6TzbJ1sduwQ=";
    };
    vendorHash = "sha256-y+eTfmZTdSkHh943o/XtFrrMWv/lxvWekKUp/JKb0h4=";
    # The repo's CI test runner is a main package and would install as `test`.
    excludedPackages = [ "scripts/test" ];
    # The fork's tests have only run on Linux.
    doCheck = super.stdenv.hostPlatform.isLinux;
  });
}
