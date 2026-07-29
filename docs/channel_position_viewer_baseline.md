# Channel Position Viewer Baseline

Captured: 2026-07-12

This records the current channel-position viewer before revising the color-coding scheme.

## Entry Point

- Dialog: `gui/lib/ui/channel_positions_dialog.dart`
- Topomap painter: `gui/lib/ui/topomap_view.dart`
- Opens as a dark modal dialog with maximum size `960 x 760`.
- The dialog title is `Channel positions`, with the dataset label underneath.

## Current Layout

- Two-panel layout inside the dialog:
  - Left panel: `Scalp map`
  - Right panel: `XYZ coordinates`
- Both panels use a low-contrast dark card treatment:
  - Fill: white at `0.04` alpha over `#111316`
  - Border: white at `0.08` alpha
  - Rounded corners: `16`
- If no channel coordinates are attached, the dialog shows:
  - `No channel coordinates are attached to this dataset yet.`

## Current Scalp Map Behavior

- The map is an interpolated topomap of one selected coordinate axis at a time.
- Default selected axis: `Y`
- Axis selector choices:
  - `X`
  - `Y`
  - `Z`
- Map background:
  - Head fill: `#0B0D10`
  - Head outline: white at `0.24` alpha
  - Subtle head overlay fill: white at `0.03` alpha
  - Nose: white at `0.18` alpha
  - Ears: white at `0.08` alpha
- Coordinate projection:
  - Uses `x` and `y` coordinates only for screen position.
  - `screenX = centerX + x * scale`
  - `screenY = centerY - y * scale`
  - Negative x appears on the left; positive x appears on the right.
- Interpolation:
  - Samples inside the head circle.
  - Inverse-distance-like weighting: `1 / (distanceSquared + softeningDistanceSquared)`.
  - Base sample step is `max(3.0, radius / 56.0)`.
  - Default sample density is `1.0`.

## Current Label Overlay

- Channel labels are shown by default.
- Labels are drawn after the interpolated field and head chrome.
- Label text:
  - Black
  - Font size `11`
  - Font weight `w700`
- Each label has a small white translucent rounded background:
  - Fill: white at `0.62` alpha
  - Inflated by `2`
  - Radius `3`
- Electrode dots exist in the painter but are hidden by default in this dialog because `showElectrodes` defaults to `false`.

## Current Color Scales

### X Axis

- Description: `Transverse / left-right`
- Legend label: `Left to right`
- Start color: `#00E5FF`
- End color: `#FF5252`
- Meaning:
  - Low x values use cyan.
  - High x values use red.

### Y Axis

- Description: `Posterior-anterior`
- Legend label: `Posterior to anterior`
- Start color: `#FF4DFF`
- End color: `#00E676`
- Meaning:
  - Low y values use magenta.
  - High y values use green.

### Z Axis

- Description: `Craniocaudal / inferior-superior`
- Legend label: `Inferior to superior`
- Start color: `#FFFF66`
- End color: `#40C4FF`
- Meaning:
  - Low z values use yellow.
  - High z values use blue.

## Current Table Behavior

- Header: `XYZ coordinates ({units})`
- Columns:
  - `Channel`
  - `X`
  - `Y`
  - `Z`
- Rows follow `timeSeries.channelLabels` order when possible, then append any coordinate keys not present in channel labels.
- Coordinate values are formatted with `toStringAsFixed(2)`.
- Coordinate cells use the same axis color function as the topomap:
  - Cell fill: axis color at `0.18` alpha
  - Cell border: axis color at `0.5` alpha
  - Text: white with tabular figures

## Functional Limits In Current Design

- Each map shows only one axis at a time, so anatomical meaning requires toggling.
- The table uses three unrelated color scales at once, which is visually rich but can be hard to interpret quickly.
- The color scales are not perceptually uniform.
- Positive/negative and anatomical direction are communicated through legend text, not through structural UI cues.
- Electrode dot markers are not shown by default; labels are the only exact channel anchors.
- The interpolation makes the view beautiful but may imply spatial continuity beyond what the coordinate table actually guarantees.
