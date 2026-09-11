# BrainStory browser preview

Build with `bash scripts/build_web.sh` from the repository root. Requires the
existing Flutter and Rust installations and the Rust target
`wasm32-unknown-unknown` (`rustup target add wasm32-unknown-unknown`).
The result is `gui/build/web`, also packaged in `dist/brainstory-web.zip`.
Serve over HTTP/HTTPS, not by opening index.html directly.

## Current scope

- Flutter workspace, pipeline editing, signal viewers, BST upload/download.
- Rust filtering, spectra, ICA fitting and ICA application compiled from the
  desktop engine's source files. Filtering and ICA fitting/application from
  the fitting node use a browser worker; other operations may still block.
- CSV, TSV, EDF, EEGLAB and BrainVision import paths. Select `.set` and `.fdt`
  together, or `.vhdr`, `.eeg`, and `.vmrk` together. Companion files must be
  selected again after a page reload if recomputing from original sources.
- Computation stays on the user's computer. The app contains no data-upload
  backend. Rendering assets and the processing engine are bundled locally.

ANT CNT remains desktop-only. Browser disk caching is not implemented; save
a BST with artifacts before closing the tab to retain computed outputs.
Large recordings have not yet been qualified for browser memory limits.
The numerical bridge currently copies JSON buffers and is a first preview,
not a completed large-recording performance port.

## Webflow

Use **Webflow Cloud**, the application hosting area, rather than pasting the
Flutter bundle into a Designer Code Embed. Webflow's documentation lists
`static` as a supported framework declaration in `webflow.json`:

```json
{"cloud":{"framework":"static"}}
```

The generated bundle needs to be published as a static application repository
with all its assets intact. Flutter and Rust are compiled locally; do not
assume Webflow's build machines have these SDKs installed. Webflow Cloud's
GitHub integration needs access to the deployment repository. This account
connection and actual deployment have not been performed or verified.

For a mount path such as `/brainstory/`, build with:
`bash scripts/build_web.sh /brainstory/`. The mount path must match the build.
For a separate application domain use the default `/` build.

If your Cloud account does not offer a static deployment, host the bundle on
a static host and link to it from Webflow, or embed its HTTPS URL in an iframe.
No recordings should be included in the deployment repository.

References:
- https://developers.webflow.com/webflow-cloud/bring-your-own-app
- https://help.webflow.com/hc/en-us/articles/33961332238611-Custom-code-embed
