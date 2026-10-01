# Python code nodes

Add **Signal Processing → Custom Code → Python Code** and connect an upstream
node. Open its configuration, select a source and interpreter, then **Save and
Run**. The included gain example works with Python's standard library; change
Parameters to `{"gain": 2.0}` to multiply signal amplitudes by two.

## Code and environment

- **Embedded in this node:** edit the entry point, import a `.py` file, or import
  a project folder. Imported files are copied into the BrainStory project,
  preserving relative paths and binary assets. The editor overrides the entry
  point file when nonempty; leave it blank to run the imported file. Review the
  expandable file list before saving. Folder imports exclude `.git`, `.venv`,
  `venv`, `__pycache__`, `node_modules`, `.DS_Store`, and symbolic links. The limit
  is 20 MB / 2,000 files; use a local folder for larger projects.
- **Local project folder:** runs the current files in that folder. Nothing is
  copied into the node. Use an entry point relative to the folder, for example
  `scripts/analyze.py`. Keep the folder available on the machine running the node.
- **Git repository:** clone an accessible HTTPS or SSH repository (or a local
  repository path) for each dataset execution. Select a commit, tag, or branch;
  blank uses remote HEAD. The exact resolved commit appears in Recent runs. Use
  a full commit ID for repeatability. Git must be installed; authentication uses
  existing credentials/SSH configuration, with terminal password prompts
  disabled. Submodules and Git LFS downloads are not managed automatically.

Choose a Python executable such as `/path/to/project/.venv/bin/python`, a Conda
environment's `bin/python`, or `C:\project\.venv\Scripts\python.exe`. A name such
as `python3` uses the desktop application's PATH. **Test interpreter** shows the
resolved executable and Python version. Use an absolute path if the application
cannot find an interpreter installed through your shell configuration.

Install dependencies into that environment yourself. BrainStory does not create
environments, activate shell profiles, or run package installation automatically.
Python and its installed packages are selected by the interpreter; other inherited
environment variables remain those of the desktop application.

Execution requires the desktop app. Code has the filesystem and network access
of your desktop account; this is not a sandbox. Only run code you trust. Python
nodes run whenever included in a requested graph run, even if previously done,
so edits to local files and changes to environments take effect. Outputs still
participate in BrainStory's normal artifact saving and loading.

## Version 1 execution contract

BrainStory invokes the interpreter directly, without a shell:

```text
<python> -u <absolute-entry-point> <absolute-input.json> <absolute-output.json>
```

The working directory is the project root. Sibling modules next to the entry
point follow normal Python import rules. Paths to input and output are also
available as `BRAINSTORY_INPUT` and `BRAINSTORY_OUTPUT`. Each dataset has a separate
temporary run directory; it is deleted after success or failure. Persistent user
files must be written to a separately chosen location by your code.

Input is UTF-8 JSON:

```json
{
  "protocolVersion": 1,
  "dataset": {"id": "dataset-id", "label": "Recording"},
  "parameters": {"gain": 2.0},
  "artifacts": {
    "timeSeries": {
      "samples": [],
      "channelSamples": [[1.0, 2.0]],
      "sampleRate": 250.0,
      "channelLabels": ["Fz"],
      "channelCoordinates": {},
      "markers": [],
      "factors": [],
      "source": "recording.csv"
    }
  }
}
```

The input contains the artifacts restored from connected upstream nodes. Ports
accept signal/spectrum, metadata artifacts, markers, and matrix transformations;
connect the ones your code needs. There is no requirement to connect all ports.
Each invocation processes one dataset, not all selected datasets together.

Write `output.json` with this envelope:

```json
{"protocolVersion": 1, "artifacts": {"featureTable": {
  "columns": ["channel", "mean"],
  "rows": [{"channel": "Fz", "mean": "1.5"}],
  "source": "custom-analysis"
}}}
```

The `artifacts` object is the **complete output**, with at least one artifact.
Copy input artifacts if they should pass through. Omitted artifacts are removed
from this node's output; unknown artifact names and null artifacts are rejected.
Dataset identity and label remain owned by BrainStory.

Supported keys use BrainStory's existing JSON representations:

| Key | Core fields |
| --- | --- |
| `timeSeries` | `samples`, `channelSamples`, `sampleRate`, `channelLabels`; optional channel coordinates, impedance data, markers, factors, source |
| `segmentedTimeSeries` | `segments`, `sampleRate`, `channelLabels` |
| `spectrum` | `frequencies`, `power`; optional channel/segment powers and labels |
| `featureTable` | `columns`, `rows` (objects keyed by column name), `source` |
| `fooofResult` | `intercept`, `exponent`, `peaks`, optional fit arrays |
| `gaussianMixture` | `featureColumns`, `assignments`, `probabilities`, `weights`, `means`, `variances`, fit metadata |
| `bridgeDetection` | `channelLabels`, `windowSampleCount`, `sampleRate`, `frames` |
| `timeFrequency` | `times`, `frequencies`, `powerMatrix`, optional channel power matrices |
| `matrixTransformation` | `matrix`, transformation matrices, source/component labels and fit metadata |

The authoritative serializers are in `gui/lib/model/data_artifacts.dart`. For
complex artifact types, begin with the corresponding input object's schema.
Markers and channel coordinates are carried inside `timeSeries`, not as separate
top-level code artifacts. Artifact identities and provenance are assigned by
BrainStory after the run; do not include them in output.

Signals use **channel-major** arrays: `channelSamples[channel][sample]`. Channels
must have equal lengths and one label per channel; `sampleRate` is positive Hz.
`samples` is the legacy single-channel representation. Populate either `samples`
or `channelSamples`, leaving the other array empty.
Spectrum frequencies and power must have equal length. Feature table values are
converted to strings by BrainStory. All numeric data must be finite; serialize
Python output with `allow_nan=False`.

## A complete feature extraction script

This produces a table while preserving upstream artifacts:

```python
import json
import sys
from pathlib import Path

request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
artifacts = request["artifacts"]
signal = artifacts["timeSeries"]
channels = signal["channelSamples"] or [signal["samples"]]
rows = []
for index, values in enumerate(channels):
    rows.append({
        "channel": signal["channelLabels"][index],
        "mean": str(sum(values) / len(values)) if values else "",
    })
artifacts["featureTable"] = {
    "columns": ["channel", "mean"], "rows": rows, "source": "python-mean"
}
Path(sys.argv[2]).write_text(
    json.dumps({"protocolVersion": 1, "artifacts": artifacts}, allow_nan=False),
    encoding="utf-8",
)
print(f"Produced {len(rows)} channel means")
```

## Failures, logs, and limits

Exit zero and write valid output to succeed. A nonzero exit, missing output,
invalid JSON/artifacts, or process timeout fails the node. BrainStory parses the
output before applying it; failed output does not partially replace input data.
Print status to stdout or stderr. Recent runs records the latest run for up to
20 datasets, elapsed time, status, error, Git revision, and up to roughly 64,000
characters of combined process output.

Timeout defaults to 300 seconds and applies separately to each Git/Python
process. A timeout kills the immediate process; code that launches independent
child processes must manage their lifecycle. Run directories are temporary,
and arbitrary generated files are not imported automatically: represent results
as supported artifacts in `output.json`.

JSON exchange currently materializes full artifacts in memory. Output is limited
to 512 MB. This first protocol does not stream arrays or use NumPy binary files;
large recordings may need a future binary transport. Code execution does not
install dependencies, provide containers, or run on remote workers.
