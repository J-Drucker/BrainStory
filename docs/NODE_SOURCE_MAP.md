# BrainStory node source map

This document points reviewers to the executable implementation of every node.
Descriptions and tests are supporting evidence; the `run`/`runChunked` path and
the functions it calls are authoritative.

## How to review a node

1. Open the node file and find its `run()` or `runChunked()` override.
2. Follow every helper called from that method, especially artifact copying and
   metadata preservation after the numerical operation.
3. If the node calls `brainstory_engine.dart`, follow the corresponding bridge
   to `engine/src/ffi.rs` and then to the named Rust module.
4. Check both normal and browser implementations under `gui/lib/platform/`.
5. Read the cited tests, then independently validate against known data or a
   trusted reference implementation. Passing internal tests is not external
   scientific validation.

## Visible nodes

| Node | Execution entry | Numerical or format core | Primary tests |
|---|---|---|---|
| Import | `gui/lib/nodes/import_node.dart` (`ImportNodeType.run`) | `gui/lib/platform/file_readers_io.dart`, `file_readers_web.dart`, `ant_cnt_import_io.dart`, `ant_cnt_import_web.dart`; ANT native reader in `engine/src/ant_cnt.rs` | `gui/test/signal_nodes_test.dart`, `gui/test/browser_source_files_test.dart` |
| Edit Channels | `gui/lib/nodes/edit_channels_node.dart` (`EditChannelsNodeType.run`) | Channel removal, interpolation, re-reference, and coordinates are implemented in the same file | `gui/test/signal_nodes_test.dart` |
| Bridge Detector | `gui/lib/nodes/bridge_detector_node.dart` (`BridgeDetectorNodeType.run`, `computeBridgeDetection`) | Pearson correlation helpers in the same file | `gui/test/signal_nodes_test.dart` |
| Resample | `gui/lib/nodes/resample_node.dart` (`ResampleNodeType.runChunked`, `resampleSignal`) | Nearest, linear, cubic interpolation, and spike suppression in the same file | `gui/test/signal_nodes_test.dart` |
| Python Code | `gui/lib/nodes/code_node.dart` (`CodeNodeType.runChunked`) | Contract in `code_contract.dart`; process execution in `gui/lib/platform/code_runner_io.dart` | `gui/test/code_node_test.dart` |
| Bandpass Filter | `gui/lib/nodes/bandpass_node.dart` (`BandpassNodeType.run`) | Bridge in `gui/lib/platform/brainstory_engine*.dart`; filter design and execution in `engine/src/filtering.rs` | Rust tests in `engine/src/filtering.rs`; `gui/test/signal_nodes_test.dart` |
| PSD | `gui/lib/nodes/psd_node.dart` (`PSDNodeType.run`, `computeSpectrum`, `computeSegmentedSpectrum`) | FFT in `engine/src/spectrum.rs`; windowing and averaging in the Dart node file | Rust tests in `engine/src/spectrum.rs`; `gui/test/signal_nodes_test.dart` |
| Spectral Features | `gui/lib/nodes/spectral_features_node.dart` (`SpectralFeaturesNodeType.run`) | Band integration and ratios in the same file | `gui/test/signal_nodes_test.dart` |
| Time-Frequency (Wavelet) | `gui/lib/nodes/time_frequency_node.dart` (`TimeFrequencyNodeType.runChunked`) | `engine/src/wavelet.rs` | Rust tests in `engine/src/wavelet.rs`; `gui/test/time_frequency_test.dart` |
| Amplitude Features | `gui/lib/nodes/amplitude_features_node.dart` (`AmplitudeFeaturesNodeType.run`) | Peak, latency, area, and variance helpers in the same file | `gui/test/signal_nodes_test.dart` |
| ICA | `gui/lib/nodes/matrix_transform_nodes.dart` (`ICANodeType.run`) | Fit/sample-selection orchestration in the Dart file; FastICA in `engine/src/ica.rs` | Rust tests in `engine/src/ica.rs`; `gui/test/ica_node_test.dart` |
| Apply ICA | `gui/lib/nodes/ica_component_rejection_node.dart` (`IcaComponentRejectionNodeType.run`) | Matrix compatibility and component selection in the Dart file; matrix application in `engine/src/ica.rs` | `gui/test/ica_node_test.dart`, `gui/test/ica_viewer_test.dart` |
| Gaussian Mixture | `gui/lib/nodes/gaussian_mixture_node.dart` (`GaussianMixtureNodeType.runChunked`) | EM implementation in `engine/src/gaussian_mixture.rs` | Rust tests in that file; `gui/test/gaussian_mixture_test.dart` |
| Edit Markers | `gui/lib/nodes/add_remove_markers_node.dart` (`AddRemoveMarkersNodeType.run`) | Boundary pairing, enumeration, recoding, and marker operations in the same file | `gui/test/signal_nodes_test.dart` |
| Edit Channels and Markers | `gui/lib/nodes/edit_channels_and_markers_node.dart` (`EditChannelsAndMarkersNodeType.run`) | Applies channel and marker operations by delegating to the edit implementations | `gui/test/signal_nodes_test.dart` |
| Recode Markers | `gui/lib/nodes/recode_markers_node.dart` (`RecodeMarkersNodeType.run`) | Label replacement in the same file | `gui/test/signal_nodes_test.dart` |
| Interactive Artifact Detection | `gui/lib/nodes/interactive_artifact_detection_node.dart` (`InteractiveArtifactDetectionNodeType.run`) | Candidate/template calculations and viewer workflow in `gui/lib/ui/visualization_panel.dart` | `gui/test/signal_nodes_test.dart` |
| Segmentation | `gui/lib/nodes/segmentation_node.dart` (`SegmentationNodeType.run`) | Event/block extraction and per-channel, per-segment baseline correction in the same file | `gui/test/signal_nodes_test.dart` |
| Realign | `gui/lib/nodes/realign_node.dart` (`RealignNodeType.run`) | Segment alignment and shifting in the same file | `gui/test/signal_nodes_test.dart` |
| Impedances | `gui/lib/nodes/impedances_node.dart` (`ImpedancesNodeType.run`) | Display preparation in the same file; rendering in `gui/lib/ui/visualization_panel.dart` | `gui/test/signal_nodes_test.dart` |

## Hidden or preliminary nodes

These files must still be reviewed, but the nodes are intentionally hidden
because they are preliminary, pass-through, or not ready for normal use.

| Node | Execution entry | Current status |
|---|---|---|
| Channel Coordinates | `gui/lib/nodes/channel_coordinates_node.dart` | Metadata operation; hidden |
| Average Spectra | `gui/lib/nodes/psd_average_node.dart` | Dart averaging; not separately exposed in the current palette |
| FOOOF | `gui/lib/nodes/fooof_node.dart` | Preliminary Dart approximation; hidden |
| PCA, Eigenvalue Decomposition, Source Reconstruction | `gui/lib/nodes/matrix_transform_nodes.dart` | Preliminary matrix-transform implementations; hidden |
| Microstates | `gui/lib/nodes/matrix_transform_nodes.dart` | Preliminary implementation; hidden |
| Detect Peaks, Interbeat Interval, Heart Rate Variability | `gui/lib/nodes/multimodal_nodes.dart` | Preliminary implementations; hidden |
| K-Means, CNN | `gui/lib/nodes/machine_learning_nodes.dart` | Preliminary implementations; hidden |
| Eye Blinks | `gui/lib/nodes/eye_blinks_node.dart` | Pass-through unless viewer-created edits provide markers; hidden |
| Sleep Staging | `gui/lib/nodes/sleep_staging_node.dart` | Preliminary implementation; hidden |
| EEG Visualization | `gui/lib/nodes/visualization_node.dart` | Viewer endpoint; hidden as a directly created node |
| Debug Output | `gui/lib/nodes/debug_output_node.dart` | Diagnostic endpoint; hidden |
| Export | `gui/lib/nodes/export_edf_node.dart`; artifact export in `gui/lib/platform/node_artifact_export.dart` | Created by export workflow rather than palette |
| Publish | `gui/lib/nodes/publish_node.dart` | Preliminary endpoint; hidden |

## Cross-cutting execution and persistence

Node-local code does not tell the entire story. Review these paths when
validating what data a node can see, when it becomes stale, and what reaches a
child:

- `gui/lib/ui/canvas_logic.dart`: scheduling, parent-only data visibility,
  artifact pass-through, stale propagation, persistence snapshots, and run
  ordering.
- `gui/lib/model/dataset.dart` and `gui/lib/model/data_artifacts.dart`: artifact
  shapes, copying, timestamps, and serialization.
- `gui/lib/nodes/node_type.dart`: common node contract and parameter-change
  semantics.
- `gui/lib/platform/brainstory_engine_io.dart` and
  `gui/lib/platform/brainstory_engine_web.dart`: desktop/native and browser/WASM
  numerical bridges.
- `engine/src/ffi.rs` and `engine/web/src/lib.rs`: exported native and browser
  engine entry points.

