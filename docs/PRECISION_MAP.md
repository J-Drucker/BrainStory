# BrainStory Precision Map

## Current policy

BrainStory stores heavy numeric artifacts at `Float32` precision when they are committed to dataset artifacts or node snapshots.

- Numeric storage target: `Float32`
- Numeric bit depth: `32-bit`
- Numeric bytes per value: `4`
- Internal intent: never exceed `4 bytes` per stored numeric value

## By stage

| Stage | Representation | Notes |
| --- | --- | --- |
| Source files on disk | Native source format | EDF is typically `int16`; BrainVision may be `int16`, `uint16`, or `float32`; ANT CNT currently arrives as `float32`; EEGLAB MAT payloads can vary |
| Import decode | `double` during parsing/math | Temporary decode representation while bytes are interpreted |
| Dataset artifact storage | `Float32` | `TimeSeriesData`, `SegmentedTimeSeriesData`, spectra, bridge matrices, time-frequency, and matrix transforms are compacted on storage |
| Node RAM snapshots | `Float32` payloads serialized through JSON | JSON adds text overhead, but the numeric payload has already been quantized to Float32-equivalent values |
| Visualization working buffers | Usually `double` during transient computation | View-only math may temporarily use Dart doubles; persisted artifacts return to Float32 |
| Export EDF | `int16` | Per-channel rescaling back into EDF digital range |

## Artifact classes

| Artifact | Stored precision |
| --- | --- |
| Time series | `Float32` |
| Segments | `Float32` |
| Spectrum / PSD | `Float32` |
| FOOOF fit vectors | `Float32` |
| Bridge correlation matrices | `Float32` |
| Time-frequency matrices | `Float32` |
| Matrix transformations | `Float32` |
| Feature tables | Text / string values |
| Markers | Integer + string metadata |

## Planned extension points

The storage model is being shaped so lower-footprint modes can be added later without changing the whole pipeline contract.

Likely future options:

- `Float32` full-resolution storage
- decimated visualization caches
- quantized `int16` storage for selected artifacts
- artifact-specific downsampling policies for previews and long recordings
