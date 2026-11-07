# shellcheck shell=bash

if (( $# == 0 )); then
  exit 0
fi

status=0
pid=""
cleanup() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for output in "$@"; do
  fuzzel \
    --dmenu \
    --prompt-only=" " \
    --output="$output" \
    --namespace=hypr-monitor-layout-poke \
    --layer=overlay \
    --lines=0 \
    --width=1 \
    --line-height=1 \
    --horizontal-pad=0 \
    --vertical-pad=0 \
    --inner-pad=0 \
    --border-width=0 \
    --background-color=00000000 \
    --text-color=00000000 \
    --prompt-color=00000000 \
    --input-color=00000000 \
    --selection-color=00000000 \
    --selection-text-color=00000000 \
    --match-color=00000000 \
    --counter-color=00000000 \
    --no-icons \
    --no-mouse \
    --keyboard-focus=on-demand \
    --log-level=none \
    >/dev/null 2>&1 &
  pid=$!

  mapped=false
  for _ in $(seq 1 100); do
    if hyprctl layers 2>/dev/null \
      | grep -Fq "namespace: hypr-monitor-layout-poke, pid: $pid"; then
      mapped=true
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.01
  done

  cleanup
  pid=""

  if [[ "$mapped" != true ]]; then
    echo "failed to map layout poke on $output" >&2
    status=1
  fi
done

exit "$status"
