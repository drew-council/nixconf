from __future__ import annotations

import json
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any


class AudioCommandError(RuntimeError):
    pass


class AudioSinkNotFoundError(AudioCommandError):
    pass


RunCommand = Callable[[list[str]], subprocess.CompletedProcess[str]]


@dataclass(frozen=True)
class AudioSink:
    id: int
    name: str
    alsa_name: str
    description: str
    selected: bool


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command, text=True, capture_output=True, check=False
    )
    if result.returncode != 0:
        message = (
            result.stderr.strip() or result.stdout.strip() or "command failed"
        )
        raise AudioCommandError(message)
    return result


def _parse_json_output(
    command: list[str], *, run: RunCommand = run_command
) -> Any:
    result = run(command)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise AudioCommandError(
            f"invalid json from {' '.join(command)}"
        ) from error


def get_default_sink_name(*, run: RunCommand = run_command) -> str:
    parsed = _parse_json_output(["pactl", "--format=json", "info"], run=run)
    if not isinstance(parsed, dict):
        raise AudioCommandError("pactl returned invalid sink info")

    default_sink_name = parsed.get("default_sink_name")
    if not isinstance(default_sink_name, str) or not default_sink_name:
        raise AudioCommandError("pactl did not return a default sink name")

    return default_sink_name


def list_sinks(*, run: RunCommand = run_command) -> list[AudioSink]:
    default_sink_name = get_default_sink_name(run=run)
    parsed = _parse_json_output(
        ["pactl", "--format=json", "list", "sinks"], run=run
    )
    if not isinstance(parsed, list):
        raise AudioCommandError("pactl returned invalid sink list")

    sinks: list[AudioSink] = []
    for row in parsed:
        if not isinstance(row, dict):
            raise AudioCommandError("pactl returned an invalid sink entry")

        properties = row.get("properties", {})
        if not isinstance(properties, dict):
            raise AudioCommandError("sink properties must be a mapping")

        name = row.get("name")
        if not isinstance(name, str) or not name:
            raise AudioCommandError("sink is missing a valid name")

        object_id = properties.get("object.id")
        try:
            sink_id = int(object_id)
        except (TypeError, ValueError) as error:
            raise AudioCommandError(
                f"sink {name!r} is missing a valid object.id"
            ) from error

        alsa_name = properties.get("alsa.name")
        if not isinstance(alsa_name, str) or not alsa_name:
            alsa_name = name

        description = row.get("description")
        if not isinstance(description, str) or not description:
            description = name

        sinks.append(
            AudioSink(
                id=sink_id,
                name=name,
                alsa_name=alsa_name,
                description=description,
                selected=name == default_sink_name,
            )
        )

    return sinks


def get_sink_by_alsa_name(
    alsa_name: str, *, run: RunCommand = run_command
) -> AudioSink:
    matches = [
        sink for sink in list_sinks(run=run) if sink.alsa_name == alsa_name
    ]
    if not matches:
        raise AudioSinkNotFoundError(
            f"no audio sink found with alsa.name {alsa_name!r}"
        )
    if len(matches) > 1:
        raise AudioCommandError(
            f"multiple audio sinks matched alsa.name {alsa_name!r}"
        )
    return matches[0]


def set_default_sink(sink_id: int, *, run: RunCommand = run_command) -> None:
    run(["wpctl", "set-default", str(sink_id)])


def set_card_profile(
    card_name: str,
    profile_name: str,
    *,
    run: RunCommand = run_command,
) -> None:
    run(["pactl", "set-card-profile", card_name, profile_name])


def switch_default_sink_by_alsa_name(
    alsa_name: str,
    *,
    card_name: str | None = None,
    card_profile: str | None = None,
    run: RunCommand = run_command,
) -> AudioSink:
    if (card_name is None) != (card_profile is None):
        raise AudioCommandError(
            "card_name and card_profile must be specified together"
        )
    if card_name is not None and card_profile is not None:
        set_card_profile(card_name, card_profile, run=run)

    sink = get_sink_by_alsa_name(alsa_name, run=run)
    set_default_sink(sink.id, run=run)
    return sink
