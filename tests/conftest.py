from __future__ import annotations

import sys
from pathlib import Path

SWITCHAUDIO = Path(__file__).resolve().parents[1] / "pkgs/switchaudio"

if str(SWITCHAUDIO) not in sys.path:
    sys.path.insert(0, str(SWITCHAUDIO))
