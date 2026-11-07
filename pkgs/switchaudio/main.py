from __future__ import annotations

import argparse
import fcntl
import os
import subprocess
import sys
import time
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from nixconf_audio import (
    AudioCommandError,
    AudioSink,
    AudioSinkNotFoundError,
    get_default_sink_name,
    list_sinks,
    set_default_sink,
    switch_default_sink_by_alsa_name,
)

PENDING_SWITCH_FILE = "switchaudio-pending"
PENDING_SWITCH_LOCK = "switchaudio-pending.lock"
RETRY_INTERVAL_SECONDS = 1.0


def runtime_dir() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")


@contextmanager
def pending_switch_lock() -> Iterator[None]:
    lock_path = runtime_dir() / PENDING_SWITCH_LOCK
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def pending_switch_path() -> Path:
    return runtime_dir() / PENDING_SWITCH_FILE


def read_pending_switch() -> str | None:
    path = pending_switch_path()
    try:
        request_id = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    return request_id or None


def queue_pending_switch() -> str:
    request_id = uuid.uuid4().hex
    with pending_switch_lock():
        pending_switch_path().write_text(request_id + "\n", encoding="utf-8")
    return request_id


def clear_pending_switch(request_id: str | None = None) -> None:
    with pending_switch_lock():
        if request_id is not None and read_pending_switch() != request_id:
            return
        pending_switch_path().unlink(missing_ok=True)


def wait_for_requested_sink(
    request_id: str,
    alsa_name: str,
    *,
    wait_seconds: float,
    card_name: str | None = None,
    card_profile: str | None = None,
    retry_interval: float = RETRY_INTERVAL_SECONDS,
) -> bool:
    deadline = time.monotonic() + wait_seconds
    last_error: AudioSinkNotFoundError | None = None

    while True:
        with pending_switch_lock():
            if read_pending_switch() != request_id:
                return False

            try:
                switch_default_sink_by_alsa_name(
                    alsa_name,
                    card_name=card_name,
                    card_profile=card_profile,
                )
            except AudioSinkNotFoundError as error:
                last_error = error
            else:
                pending_switch_path().unlink(missing_ok=True)
                return True

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AudioCommandError(
                f"timed out waiting for audio sink {alsa_name!r}"
            ) from last_error
        time.sleep(min(retry_interval, remaining))


def format_choices() -> tuple[list[str], list[AudioSink]]:
    sinks = list_sinks()
    defaults = [sink for sink in sinks if sink.selected]
    if len(defaults) != 1:
        raise AudioCommandError("expected exactly one selected default sink")

    alsa_width = max(len(sink.alsa_name) for sink in sinks)
    choices = [
        (
            f"{'✅' if sink.selected else '  '} "
            f"{sink.alsa_name.ljust(alsa_width)} {sink.description}"
        )
        for sink in sinks
    ]
    return choices, sinks


def pick_sink() -> int | None:
    choices, sinks = format_choices()
    result = subprocess.run(
        ["fuzzel", "--dmenu", "--index", "--use-bold", "--width=50"],
        input="\n".join(choices),
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return None

    selected = result.stdout.strip()
    if not selected:
        return None

    try:
        index = int(selected)
    except ValueError as error:
        raise AudioCommandError(
            "fuzzel returned a non-numeric selection"
        ) from error

    if index < 0 or index >= len(sinks):
        raise AudioCommandError("fuzzel returned an invalid selection")

    selected_sink = sinks[index]
    set_default_sink(selected_sink.id)

    if get_default_sink_name() != selected_sink.name:
        raise AudioCommandError("failed to update the default audio sink")

    print(
        {
            "id": selected_sink.id,
            "name": selected_sink.name,
            "alsa_name": selected_sink.alsa_name,
            "description": selected_sink.description,
        }
    )
    return index


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--alsa-name",
        help="Switch to the sink whose PipeWire ALSA name matches.",
    )
    parser.add_argument(
        "--card-name",
        help="Activate this PipeWire card before selecting the sink.",
    )
    parser.add_argument(
        "--card-profile",
        help="Activate this PipeWire card profile before selecting the sink.",
    )
    parser.add_argument(
        "--wait",
        type=float,
        metavar="SECONDS",
        help="Wait for the requested ALSA sink to become available.",
    )
    args = parser.parse_args()

    if args.wait is not None and args.alsa_name is None:
        parser.error("--wait requires --alsa-name")
    if args.wait is not None and args.wait <= 0:
        parser.error("--wait must be greater than zero")

    request_id = None
    try:
        if args.wait is not None:
            request_id = queue_pending_switch()
            wait_for_requested_sink(
                request_id,
                args.alsa_name,
                wait_seconds=args.wait,
                card_name=args.card_name,
                card_profile=args.card_profile,
            )
        else:
            clear_pending_switch()
            if args.alsa_name is not None:
                switch_default_sink_by_alsa_name(
                    args.alsa_name,
                    card_name=args.card_name,
                    card_profile=args.card_profile,
                )
            else:
                pick_sink()
    except AudioCommandError as error:
        print(error, file=sys.stderr)
        return 1
    finally:
        if request_id is not None:
            clear_pending_switch(request_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
