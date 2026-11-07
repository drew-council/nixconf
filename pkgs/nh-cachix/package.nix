{
  bash,
  cachix,
  coreutils,
  lib,
  nh,
  writeShellApplication,
}:

writeShellApplication {
  name = "nh";
  excludeShellChecks = [ "SC2016" ];
  text = ''
    if [[ "''${1-}" != "os" && "''${1-}" != "darwin" ]]; then
      exec ${lib.getExe nh} "$@"
    fi

    status_file="$(${lib.getExe' coreutils "mktemp"})"
    link_dir="$(${lib.getExe' coreutils "mktemp"} -d)"
    cleanup() {
      ${lib.getExe' coreutils "rm"} -rf "$status_file" "$link_dir"
    }
    trap cleanup EXIT

    # watch-exec gives in-flight uploads only 60s once nh exits, which drops
    # large paths. Keep the result so its closure can be pushed afterwards.
    out_link=""
    args=("$@")
    case "''${2-}" in
      switch | boot | test | build)
        has_out_link=""
        for arg in "''${@:3}"; do
          case "$arg" in
            --) break ;;
            -o | --out-link | --out-link=*) has_out_link=1 ;;
          esac
        done
        if [[ -z "$has_out_link" ]]; then
          out_link="$link_dir/result"
          args=("$1" "$2" --out-link "$out_link" "''${@:3}")
        fi
        ;;
    esac
    set -- "''${args[@]}"

    set +e
    NH_CACHIX_STATUS_FILE="$status_file" \
      ${lib.getExe cachix} watch-exec \
        --watch-mode post-build-hook \
        bizmythy-nixconf -- \
        ${lib.getExe bash} -c '
          "$@"
          status=$?
          printf "%s\n" "$status" > "$NH_CACHIX_STATUS_FILE"
          exit "$status"
        ' bash ${lib.getExe nh} "$@"
    cachix_status=$?
    set -e

    nh_status=""
    if [[ -s "$status_file" ]]; then
      read -r nh_status < "$status_file"
    fi

    if [[ -n "$nh_status" ]]; then
      if ((nh_status != 0)); then
        exit "$nh_status"
      fi

      if [[ -n "$out_link" && -e "$out_link" ]]; then
        set +e
        ${lib.getExe cachix} push bizmythy-nixconf \
          "$(${lib.getExe' coreutils "readlink"} -f "$out_link")"
        cachix_status=$?
        set -e
      fi

      if ((cachix_status != 0)); then
        printf \
          'warning: nh succeeded, but pushing to Cachix failed (exit %s)\n' \
          "$cachix_status" >&2
      fi
      exit 0
    fi

    printf \
      'warning: Cachix failed before nh started; continuing without upload\n' \
      >&2
    exec ${lib.getExe nh} "$@"
  '';

  meta = {
    description = "nh with automatic Cachix uploads for NixOS and nix-darwin commands";
    inherit (nh.meta) homepage license;
    mainProgram = "nh";
  };
}
// {
  inherit (nh) version;
}
