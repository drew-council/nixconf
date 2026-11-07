#!/usr/bin/env python3
"""Select a Hyprland monitor profile and queue it for the Lua applier."""

from __future__ import annotations

import json
import logging
import os
import subprocess
import time
from pathlib import Path
from typing import Any

import click

PROMPT = "Monitors> "
REQUEST_FILE = "hyprmonitor-profile-request"
LOG_FILE = "hypr-monitor-profile.log"
LOGGER = logging.getLogger(__name__)


def runtime_dir() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")


def setup_logging() -> None:
    logging.basicConfig(
        filename=runtime_dir() / LOG_FILE,
        level=logging.INFO,
        format="[%(asctime)s] %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z",
    )


def load_config(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def choose_profile(labels: list[str]) -> str | None:
    result = subprocess.run(
        ["fuzzel", "--dmenu", "--prompt", PROMPT],
        input="\n".join(labels) + "\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )

    if result.returncode != 0:
        LOGGER.info("fuzzel exited with %s", result.returncode)
        return None

    choice = result.stdout.strip()
    if not choice:
        LOGGER.info("no profile selected")
        return None

    return choice


def set_tablet_headless(enabled: bool, output_name: str) -> None:
    if enabled:
        action = ["create", "headless", output_name]
    else:
        action = ["remove", output_name]
    result = subprocess.run(
        ["hyprctl", "output", *action],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )

    if result.stdout:
        for line in result.stdout.splitlines():
            LOGGER.info("hyprctl: %s", line)


def notify(summary: str, body: str) -> None:
    subprocess.run(["notify-send", summary, body], check=False)


def queue_profile_request(label: str) -> None:
    request_id = str(time.time_ns())
    (runtime_dir() / REQUEST_FILE).write_text(
        f"{request_id}\n{label}\n",
        encoding="utf-8",
    )
    LOGGER.info("queued request %s for %s", request_id, label)


@click.command(help=__doc__)
@click.option(
    "--profiles-json",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    required=True,
    help="JSON file describing available monitor profiles",
)
@click.argument("profile_label", required=False)
def main(profiles_json: Path, profile_label: str | None) -> None:
    setup_logging()
    config = load_config(profiles_json)
    profiles = {profile["label"]: profile for profile in config["profiles"]}
    labels = list(profiles)

    LOGGER.info(
        "launch WAYLAND_DISPLAY=%s DISPLAY=%s XDG_RUNTIME_DIR=%s",
        os.environ.get("WAYLAND_DISPLAY", ""),
        os.environ.get("DISPLAY", ""),
        os.environ.get("XDG_RUNTIME_DIR", ""),
    )

    choice = profile_label or choose_profile(labels)
    if choice is None:
        return

    profile = profiles.get(choice)
    if profile is None:
        notify("hyprmonitor", f"unknown monitor profile: {choice}")
        raise click.ClickException(f"unknown monitor profile: {choice}")

    LOGGER.info("selected %s", choice)
    set_tablet_headless(
        bool(profile.get("useTablet")),
        config["tabletHeadlessName"],
    )
    queue_profile_request(choice)


if __name__ == "__main__":
    main()
