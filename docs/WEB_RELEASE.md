# BrainStory browser preview

Build with `bash scripts/build_web.sh` from the repository root. Requires the
existing Flutter and Rust installations, an activated Emscripten SDK (`emcc`),
and the Rust target
`wasm32-unknown-unknown` (`rustup target add wasm32-unknown-unknown`).
The result is `gui/build/web`, also packaged in `dist/brainstory-web.zip`.
Serve over HTTP/HTTPS, not by opening index.html directly.

## Current scope

- Flutter workspace, pipeline editing, signal viewers, BST upload/download.
- Rust filtering, spectra, ICA fitting and ICA application compiled from the
  desktop engine's source files. Filtering and ICA fitting/application from
  the fitting node use a browser worker; other operations may still block.
- CSV, TSV, EDF, ANT Neuro CNT, EEGLAB and BrainVision import paths. Select `.set` and `.fdt`
  together, or `.vhdr`, `.eeg`, and `.vmrk` together. Companion files must be
  selected again after a page reload if recomputing from original sources.
- Computation stays on the user's computer. The app contains no data-upload
  backend. Rendering assets and the processing engine are bundled locally.

ANT CNT parsing uses the vendored libeep reader compiled to WebAssembly and
runs inside a browser worker; recordings are not uploaded. Browser disk caching
is not implemented; save a BST with artifacts before closing the tab to retain computed outputs.
Large recordings have not yet been qualified for browser memory limits.
The numerical bridge currently copies JSON buffers and is a first preview,
not a completed large-recording performance port.

## Webflow

The deployment project is `packaging/webflow`. It uses Webflow's documented
Vite integration and contains the compiled Flutter/Rust release in
`brainstory-web.zip`. No Flutter or Rust installation is needed on Webflow.
The archive contains app code and assets, not recordings or saved projects.

One-time account setup:

1. Open the Webflow dashboard, choose New Project > App > Connect GitHub.
2. Sign in to GitHub and authorize Webflow for `J-Drucker/BrainStory` only.
3. After the prepared commit has been pushed, import that repository.
4. Name the app `BrainStory`, select branch `main`, and set the root directory
   in Advanced settings to `packaging/webflow`.
5. Use framework Vite and the default build/output settings (`npm run build`,
   `dist`) if prompted. No environment variables or database bindings are needed.
6. Deploy, then open the generated application URL. A standalone app is suitable
   for the first friends-only preview. It can later be linked from the
   HumanNexus Neuroscience site.

Webflow provides the mount path to Vite. The wrapper uses that path to open
the workspace; the workspace resolves its assets relative to its own directory.
Both `/` and a path such as `/brainstory/` are supported without rebuilding Rust.

To publish future code changes, run `bash scripts/prepare_webflow.sh`, commit
the changed source and `packaging/webflow/brainstory-web.zip`, then push when
ready to deploy. A source-only push does not refresh the compiled release.
The build configuration unpacks the archive during Vite configuration, so it
also works when Webflow invokes Vite directly rather than an npm lifecycle hook.

Local wrapper check (Node 22.12 or newer): run `npm ci`, `npm run build`, and
`npm run preview` from `packaging/webflow`. The `public`, `dist`, and
`node_modules` folders are generated and ignored by Git.

Account connection and a hosted deployment still require verification. The
Webflow Designer/API connection alone does not grant Cloud access to GitHub.

References:
- https://developers.webflow.com/webflow-cloud/bring-your-own-app
- https://developers.webflow.com/webflow-cloud/environment/framework-customization
- https://help.webflow.com/hc/en-us/articles/33961332238611-Custom-code-embed
