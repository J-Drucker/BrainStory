"""Export ANT Neuro CNT data through MNE into a BrainStory-friendly payload.

This intentionally stays tiny: BrainStory owns the UI and data model, while
MNE/antio/libeep handle the ANT CNT file-format details.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path


def _marker_type(description: str, duration_seconds: float) -> str:
    lower = description.lower()
    if "bad" in lower or "artifact" in lower:
        return "artifact"
    if duration_seconds <= 0:
        return "event"
    return "window"


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: import_ant_cnt.py <ANT Neuro .cnt file>", file=sys.stderr)
        return 64

    cnt_path = Path(sys.argv[1]).expanduser().resolve()
    if not cnt_path.exists():
        print(f"CNT file does not exist: {cnt_path}", file=sys.stderr)
        return 66

    try:
        import mne
        import numpy as np
    except Exception as exc:  # pragma: no cover - exercised by app runtime.
        print(
            "ANT CNT import requires Python packages mne>=1.9 and antio "
            "(which uses libeep). Install them in BrainStory's Python environment.",
            file=sys.stderr,
        )
        print(str(exc), file=sys.stderr)
        return 69

    try:
        raw = mne.io.read_raw_ant(str(cnt_path), preload=True, verbose="ERROR")
    except AttributeError:
        print(
            "This MNE version does not expose mne.io.read_raw_ant. "
            "Install MNE >= 1.9 and antio.",
            file=sys.stderr,
        )
        return 69
    except Exception as exc:
        print(f"Failed to read ANT CNT file with MNE: {exc}", file=sys.stderr)
        return 65

    # MNE stores EEG-like channels in volts. BrainStory's current viewers and
    # exports expect microvolt-scale values, matching the rest of the importers.
    data = raw.get_data() * 1_000_000.0
    data = np.asarray(data, dtype="<f4", order="C")

    output_dir = Path(tempfile.mkdtemp(prefix="brainstory_ant_cnt_"))
    samples_file = output_dir / "samples.f32"
    data.tofile(samples_file)

    markers = []
    for annotation in raw.annotations:
        description = str(annotation["description"])
        duration = float(annotation["duration"])
        markers.append(
            {
                "label": description,
                "onsetMicros": round(float(annotation["onset"]) * 1_000_000.0),
                "durationMicros": round(duration * 1_000_000.0),
                "markerType": _marker_type(description, duration),
                "attributes": {"source": "ANT CNT"},
            }
        )

    payload = {
        "sourceDescription": str(cnt_path),
        "sampleRate": float(raw.info["sfreq"]),
        "channelLabels": list(raw.ch_names),
        "channelCount": int(data.shape[0]),
        "sampleCount": int(data.shape[1]),
        "units": "uV",
        "samplesFile": str(samples_file),
        "tempDir": str(output_dir),
        "markers": markers,
    }
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
