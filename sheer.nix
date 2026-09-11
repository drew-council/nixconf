{
  lib,
  pkgs,
  platform,
  vars,
  ...
}:

let
  cache = "${vars.home}/.cache/bazel";
  # Time Machine skips /var/tmp, so macOS keeps the large output_base there.
  outputBaseRoot = if platform.isDarwin then "/private/var/tmp" else "/var/tmp";
in
{
  # Tools from the sheer repo's Brewfile / scripts/setup.sh that are not
  # already installed globally (buf, go, gopls, nodejs 24, and docker-buildx
  # come from home/packages/terminal.nix).
  home.packages = with pkgs; [
    bazelisk
    # Homebrew symlinks bazel -> bazelisk; the nixpkgs package only ships
    # a bazelisk binary, so provide the bazel name ourselves.
    (writeShellScriptBin "bazel" ''exec ${lib.getExe bazelisk} "$@"'')
    delve
    firebase-tools
    google-cloud-sdk
    opentofu
    pnpm_10 # repo pins packageManager pnpm@10.x
    pulumi
  ];

  # Bazel does not expand ~ or $HOME in .bazelrc, so every path is absolute.
  home.file.".bazelrc".text = ''
    # One output_base per worktree (hashed from the workspace path) under
    # outputBaseRoot, so every worktree keeps its own long-lived server. A Bazel
    # server is bound to a single workspace, so a shared output_base would make
    # worktrees kill each other's server. Cross-worktree reuse comes from the
    # content-addressed caches below instead.
    startup --output_user_root=${outputBaseRoot}/_bazel_${vars.user}

    common --repository_cache=${cache}/repo-cache
    common --experimental_repository_cache_hardlinks
    common --repo_contents_cache=${cache}/repo-contents-cache

    build --disk_cache=${cache}/disk-cache
    test  --disk_cache=${cache}/disk-cache
    # Garbage-collect the disk cache in the background once the server idles,
    # so it stays under this size instead of growing without bound.
    common --experimental_disk_cache_gc_max_size=50G
  '';
}
