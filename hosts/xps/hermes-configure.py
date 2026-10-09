"""Merge Nix-managed Hermes settings without making its runtime config read-only."""

import json
import os
import sys
import tempfile
from pathlib import Path

import yaml


def merge(existing, managed):
    for key, value in managed.items():
        if isinstance(value, dict):
            child = existing.get(key)
            if not isinstance(child, dict):
                child = {}
            existing[key] = merge(child, value)
        else:
            existing[key] = value
    return existing


def main():
    source, destination = map(Path, sys.argv[1:])
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    existing = {}
    if destination.exists():
        try:
            existing = yaml.safe_load(destination.read_text()) or {}
        except yaml.YAMLError:
            raise SystemExit("Invalid Hermes config; refusing to overwrite it.")
        if not isinstance(existing, dict):
            raise SystemExit("Hermes config must be a mapping.")
    managed = json.loads(source.read_text())
    desired = merge(existing, managed)
    fd, temporary = tempfile.mkstemp(
        prefix=".config-nix-", dir=destination.parent
    )
    try:
        with os.fdopen(fd, "w") as output:
            yaml.safe_dump(desired, output, sort_keys=False)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()
