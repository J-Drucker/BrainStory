# brainstory_gui

Flutter desktop UI for BrainStory.

## ANT CNT Import

ANT Neuro `.cnt` files are imported natively by the Rust engine, which bundles
an unmodified copy of LIBEEP. This preserves channel data, event markers, and
time-stamped impedance measurements without requiring Python, MNE, or antio.

LIBEEP is LGPL-3.0 with ANT's static-linking addendum. Its source and license
notices are in `../engine/vendor/libeep/`.

The app does not fall back to Python for ANT CNT imports. A missing native
engine is reported immediately instead of launching an external importer.
