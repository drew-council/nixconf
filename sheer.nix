{
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
    # The repo's Brewfile uses bazelisk, but nixpkgs bazel_8 currently matches
    # the pinned .bazelversion (8.7.0) exactly, so use it instead of letting
    # bazelisk download an upstream binary at runtime. Plain bazel ignores
    # .bazelversion, so keep these in sync manually when the repo bumps it.
    bazel_8
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
