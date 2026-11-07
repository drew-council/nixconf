{
  flake.modules.homeManager.work =
    { lib, pkgs, ... }:
    {
      # Tools from the sheer repo's Brewfile / scripts/setup.sh that the
      # terminal feature does not already install.
      home.packages =
        with pkgs;
        [
          delve # Go debugger
          firebase-tools # Firebase CLI
          gnumake # everything is driven through the repo Makefile
          google-cloud-sdk # gcloud CLI
          opentofu # infrastructure as code
          pnpm_12 # repo pins packageManager pnpm@12.x
          # nixpkgs pulumi ships only the CLI; `pulumi up` on a `runtime: go`
          # project needs the pulumi-language-go host on PATH too.
          (pulumi.withPackages (ps: [ ps.pulumi-go ]))
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          # C compiler for cgo outside Bazel (e.g. golangci-lint via `go tool`). On
          # macOS the Xcode CLT clang fills this role; a nixpkgs gcc would shadow
          # it on PATH. Inside Bazel the compiler comes from bazelActionPath.
          pkgs.gcc
          # `bazel run` of py_binary targets (e.g. //:format's multirun) execs the
          # rules_python stub with the client PATH; its `#!/usr/bin/env python3`
          # needs any python3 there before it re-execs the hermetic interpreter.
          pkgs.python3
        ];
    };
}
