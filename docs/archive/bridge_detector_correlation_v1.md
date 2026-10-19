# Archived bridge detector: minute correlation (v1)

Archived on 2026-10-18 when BrainStory replaced this method with the
epochwise mean-squared-difference detector implemented in Rust.

The original implementation is preserved in Git at commit `d7d6cf4`. Its
runtime source was `gui/lib/nodes/bridge_detector_node.dart`.

## Original algorithm

1. Divide the recording into complete one-minute blocks.
2. Take the final `windowSamples` samples of each minute (default 1000).
3. Compute a full Pearson correlation matrix across channels for each block.
4. Display each matrix as a heatmap, optionally reordering channels using the
   average positive covariance structure.

This archive is documentation only. No current node imports or executes the
old Dart implementation.
