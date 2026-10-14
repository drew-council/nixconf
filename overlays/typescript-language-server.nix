# typescript-language-server 6.0.2 in nixpkgs-unstable has a stale pnpmDeps
# hash (fixed on master in ac7b1aaed0, not yet on nixos-unstable).
# The pnpm store dump isn't platform-independent, so pin a hash per
# platform. Drop this once unstable propagates the upstream hash fix.
self: super:
let
  hash =
    if super.stdenv.hostPlatform.isDarwin then
      "sha256-PmyJb8090pEPc09Tbv8RgdvQpzpba2L8ve87+aVncQU="
    else
      "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
in
{
  typescript-language-server = super.typescript-language-server.override {
    # Wrap rather than `.override { hash }`: the fetcher's override goes
    # through nixpkgs' outer callPackage wrapper, which rejects `hash`.
    fetchPnpmDeps = args: super.fetchPnpmDeps (args // { inherit hash; });
  };
}
