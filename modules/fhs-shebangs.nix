{ pkgs, ... }:

# Hardcoded FHS shebangs that NixOS does not provide by default. NixOS only
# ships /bin/sh and /usr/bin/env, but some prebuilt or generated tooling execs
# other fixed paths and does so with an empty environment, so neither PATH nor
# nix-ld can help. Today this is driven by the sheer repo's Bazel setup
# (see ../sheer.nix):
#
# - toolchains_llvm's cc_wrapper.sh and Bazel's own `run` command exec
#   /bin/bash directly.
# - rules_python's default bootstrap stub starts with `#!/usr/bin/env python3`
#   and some py_binary actions run with use_default_shell_env = False, i.e. no
#   PATH at all, so env falls back to /bin:/usr/bin. The stub only needs any
#   python3 to bootstrap; it re-execs the hermetic interpreter afterwards.
{
  systemd.tmpfiles.settings."10-fhs-shebangs" = {
    "/bin/bash"."L+".argument = "${pkgs.bash}/bin/bash";
    "/usr/bin/python3"."L+".argument = "${pkgs.python3}/bin/python3";
  };
}
