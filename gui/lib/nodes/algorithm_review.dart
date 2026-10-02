enum AlgorithmImplementation { passThrough, toy, dart, rust, external }

extension AlgorithmImplementationLabel on AlgorithmImplementation {
  String get label => switch (this) {
    AlgorithmImplementation.passThrough => 'Pass-through',
    AlgorithmImplementation.toy => 'Preliminary',
    AlgorithmImplementation.dart => 'Dart',
    AlgorithmImplementation.rust => 'Rust',
    AlgorithmImplementation.external => 'External code',
  };
}

class AlgorithmReview {
  const AlgorithmReview({
    required this.implementation,
    required this.summary,
    required this.procedure,
    required this.parameters,
    required this.assumptions,
    required this.sourceFiles,
    this.testFiles = const <String>[],
  });

  final AlgorithmImplementation implementation;
  final String summary;
  final List<String> procedure;
  final List<String> parameters;
  final List<String> assumptions;
  final List<String> sourceFiles;
  final List<String> testFiles;
}

const Map<String, AlgorithmReview>
nodeAlgorithmReviews = <String, AlgorithmReview>{
  'Bandpass Filter': AlgorithmReview(
    implementation: AlgorithmImplementation.rust,
    summary:
        'Zero-phase Butterworth high-pass and low-pass sections, with an optional biquad notch, applied independently to every continuous channel.',
    procedure: <String>[
      'Map steepness to Butterworth order 2, 4, 6, or 8.',
      'Construct cascaded second-order high-pass and low-pass sections. Add one notch section when requested.',
      'Odd-reflection pad the signal by at least six samples per section and approximately ten cycles of the slowest cutoff.',
      'Filter forward, reverse, filter again, reverse again, and remove the padding. This squares the magnitude response and cancels phase delay.',
      'Preserve channel labels, coordinates, impedances, markers, and factors; invalidate inherited segments.',
    ],
    parameters: <String>[
      'Low cut and high cut: Hz; zero disables that edge.',
      'Steepness: 0-1, mapped to order 2 (<0.25), 4 (<0.75), 6 (<0.9), or 8.',
      'Notch: optional Hz. Q = max(1, 0.6 + 3.4 x steepness).',
    ],
    assumptions: <String>[
      'All values must be finite and cutoffs must lie below Nyquist.',
      'Forward/backward operation is acausal and intended for offline data.',
      'The effective filter order is doubled by forward/backward filtering.',
    ],
    sourceFiles: <String>[
      'gui/lib/nodes/bandpass_node.dart',
      'engine/src/filtering.rs',
    ],
    testFiles: <String>[
      'engine/src/filtering.rs',
      'gui/test/signal_nodes_test.dart',
    ],
  ),
  'PSD': AlgorithmReview(
    implementation: AlgorithmImplementation.rust,
    summary:
        'Welch-style single-sided power estimate over explicit input segments, using mean removal, Hann windows, 50% overlap, and an FFT.',
    procedure: <String>[
      'For each input segment and channel, choose the largest power-of-two window no larger than min(segment length, 256), with a minimum target of 32 samples.',
      'Advance windows by half their length (50% overlap). Mean-center and Hann-window each window.',
      'Compute the real FFT and retain bins in the requested frequency range.',
      'Compute power as squared complex magnitude divided by window sample count.',
      'Average windows within a segment, then optionally average across segments. Per-segment and per-channel values are retained.',
    ],
    parameters: <String>[
      'Low and high frequency: Hz, inclusive.',
      'Output mode controls whether segment spectra are retained or averaged.',
      'Parent-segment mode selects an upstream segmentation artifact; otherwise the node creates equal windows.',
    ],
    assumptions: <String>[
      'The current output is power per FFT bin, not a calibrated power spectral density per Hz.',
      'Segments shorter than the chosen window are zero-padded to one window.',
      'Frequency resolution is sample rate divided by FFT window length.',
    ],
    sourceFiles: <String>[
      'gui/lib/nodes/psd_node.dart',
      'engine/src/spectrum.rs',
    ],
    testFiles: <String>[
      'engine/src/spectrum.rs',
      'gui/test/signal_nodes_test.dart',
    ],
  ),
  'Time-Frequency (Wavelet)': AlgorithmReview(
    implementation: AlgorithmImplementation.rust,
    summary:
        'Morlet-wavelet power sampled on bounded, evenly spaced frequency and time grids.',
    procedure: <String>[
      'Subtract the channel mean.',
      'Generate linearly spaced frequencies and evenly sampled output times.',
      'At each frequency, set Gaussian sigma to cycles / (2 pi frequency) and truncate the kernel at 3.5 sigma.',
      'Accumulate real and imaginary Morlet responses and report (real² + imaginary²) divided by the squared Gaussian norm.',
    ],
    parameters: <String>[
      'Frequency bounds: Hz; upper bound cannot exceed Nyquist.',
      'Frequency bins: 1-128. Time bins: 1-2048.',
      'Cycles: 2-20; larger values improve frequency resolution and reduce time resolution.',
    ],
    assumptions: <String>[
      'Frequency spacing is linear, not logarithmic.',
      'The kernel is truncated at recording boundaries without reflection padding.',
      'Output is normalized wavelet power, not baseline-normalized dB power.',
    ],
    sourceFiles: <String>[
      'gui/lib/nodes/time_frequency_node.dart',
      'engine/src/wavelet.rs',
    ],
    testFiles: <String>[
      'engine/src/wavelet.rs',
      'gui/test/time_frequency_test.dart',
    ],
  ),
  'ICA': AlgorithmReview(
    implementation: AlgorithmImplementation.rust,
    summary:
        'Symmetric FastICA with covariance-eigenvalue whitening, tanh nonlinearity, deterministic initialization, and rank-aware component limits.',
    procedure: <String>[
      'Select the requested channels and samples from the whole recording, a time portion, or complete marker-relative windows.',
      'Subtract each channel mean and eigendecompose the channel covariance matrix.',
      'Discard eigenvalues at or below max(largest eigenvalue x 1e-12, machine epsilon), then whiten to the requested component count.',
      'Initialize deterministically from the seed and iterate symmetric FastICA with tanh nonlinearity and symmetric decorrelation.',
      'Stop when the maximum component alignment change is below tolerance or the iteration limit is reached; normalize and store mixing/unmixing matrices.',
    ],
    parameters: <String>[
      'Components: zero uses numerical rank; otherwise cannot exceed rank.',
      'Tolerance: maximum absolute 1 - component alignment required for convergence.',
      'Fit scope and marker windows: seconds relative to marker onset; all samples in each nonzero-duration/window selection are concatenated.',
      'Seed controls deterministic initialization.',
    ],
    assumptions: <String>[
      'Requires at least two linearly independent channels.',
      'ICA component order and sign are not intrinsically identifiable.',
      'A model fitted on selected samples is applied to the full compatible signal for component activations.',
    ],
    sourceFiles: <String>[
      'gui/lib/nodes/matrix_transform_nodes.dart',
      'engine/src/ica.rs',
    ],
    testFiles: <String>['engine/src/ica.rs', 'gui/test/ica_node_test.dart'],
  ),
  'Apply ICA': AlgorithmReview(
    implementation: AlgorithmImplementation.rust,
    summary:
        'Applies a stored ICA unmixing matrix to compatible channel-major data after subtracting the fitted channel means.',
    procedure: <String>[
      'Match input channels to the model metadata and reject incompatible data.',
      'Subtract the channel means stored with the ICA fit.',
      'Multiply the centered channel vector by the row-major unmixing matrix at every sample.',
      'Emit component activations while preserving compatible timing metadata.',
    ],
    parameters: <String>[
      'The selected matrix source identifies the fitted ICA model.',
    ],
    assumptions: <String>[
      'Channel names, order, and dimensionality must match the fitted model metadata.',
      'Applying a model to a different dataset is valid only when acquisition and preprocessing are compatible.',
    ],
    sourceFiles: <String>[
      'gui/lib/nodes/matrix_transform_nodes.dart',
      'engine/src/ica.rs',
    ],
    testFiles: <String>['engine/src/ica.rs', 'gui/test/ica_node_test.dart'],
  ),
  'Segmentation': AlgorithmReview(
    implementation: AlgorithmImplementation.dart,
    summary:
        'Extracts marker-locked epochs or duration-bearing blocks while keeping conditions separate; optional baseline correction is performed independently for every segment and channel.',
    procedure: <String>[
      'Resolve selected marker labels and convert requested time bounds to sample indexes.',
      'Create one bounded segment per eligible event or block; optionally reject segments overlapping bad-marker intervals.',
      'For event baselining, intersect the requested baseline interval with the segment.',
      'For each segment and each channel, compute that channel’s arithmetic mean over its baseline samples and subtract it from every sample in that channel’s segment.',
      'If no baseline samples remain after clipping, subtract the channel value at the event anchor.',
    ],
    parameters: <String>[
      'Event start/stop and baseline start/stop: milliseconds relative to marker onset.',
      'Bad-marker exclusion uses interval overlap, not marker label as a condition.',
      'Block concatenation concatenates only within the same condition.',
    ],
    assumptions: <String>[
      'Sample indexes are rounded from time x sample rate and clipped to recording bounds.',
      'Baseline correction changes stored segment values when enabled; it is not display-only.',
    ],
    sourceFiles: <String>['gui/lib/nodes/segmentation_node.dart'],
    testFiles: <String>['gui/test/signal_nodes_test.dart'],
  ),
  'Resample': AlgorithmReview(
    implementation: AlgorithmImplementation.dart,
    summary:
        'Resamples each channel on a new regular time grid using nearest-neighbor, linear, or four-point cubic interpolation.',
    procedure: <String>[
      'Compute output length as round(input length / source rate x target rate).',
      'For output sample i, evaluate the source at i x source rate / target rate.',
      'Interpolate by the selected method. Optional spike suppression replaces strong local outliers before interpolation.',
      'Copy marker times unchanged because markers are stored in time units rather than sample indexes.',
    ],
    parameters: <String>[
      'New sample rate: Hz and greater than zero.',
      'Method: nearest, linear, or cubic spline (implemented as local four-point cubic interpolation).',
    ],
    assumptions: <String>[
      'No anti-alias low-pass filter is currently applied before downsampling.',
      'Cubic interpolation is local and is not a global fitted spline.',
    ],
    sourceFiles: <String>['gui/lib/nodes/resample_node.dart'],
    testFiles: <String>['gui/test/signal_nodes_test.dart'],
  ),
  'Bridge Detector': AlgorithmReview(
    implementation: AlgorithmImplementation.dart,
    summary:
        'Computes a Pearson channel-correlation matrix from the final requested samples of each complete recording minute.',
    procedure: <String>[
      'Divide the recording into complete 60-second intervals; ignore a trailing partial minute.',
      'Take the last min(window size, samples per minute) samples from every channel in each minute.',
      'Compute the ordinary Pearson correlation for every channel pair.',
      'Store one symmetric correlation matrix per complete minute.',
    ],
    parameters: <String>['Window size: samples, default 1000.'],
    assumptions: <String>[
      'Constant-valued channels receive correlation zero rather than undefined.',
      'This node reports correlations; it does not itself classify or remove bridged channels.',
    ],
    sourceFiles: <String>['gui/lib/nodes/bridge_detector_node.dart'],
    testFiles: <String>['gui/test/signal_nodes_test.dart'],
  ),
  'Gaussian Mixture': AlgorithmReview(
    implementation: AlgorithmImplementation.rust,
    summary:
        'Deterministic expectation-maximization fit of a diagonal-covariance Gaussian mixture to feature-table rows.',
    procedure: <String>[
      'Select numeric feature columns and optionally standardize each to zero mean and unit population standard deviation.',
      'Initialize component means deterministically from data rows using the seed; initialize equal weights and global diagonal variance.',
      'Alternate log-sum-exp responsibility calculation (E step) and weighted means, variances, and weights (M step).',
      'Stop when absolute log-likelihood change <= tolerance x (1 + |previous log likelihood|), or at the iteration limit.',
      'Return posterior probabilities, maximum-posterior assignments, weights, means, diagonal variances, log likelihood, AIC, and BIC.',
    ],
    parameters: <String>[
      'Components: 1-32 and no greater than row count.',
      'Regularization: positive value added to each variance.',
      'AIC/BIC parameter count: (K - 1) + 2 K D for K components and D features.',
    ],
    assumptions: <String>[
      'Features are conditionally independent within each component because covariance is diagonal.',
      'Rows with missing, nonnumeric, or nonfinite selected features are rejected rather than imputed.',
      'Cluster numbers have no ordinal meaning.',
    ],
    sourceFiles: <String>[
      'gui/lib/nodes/gaussian_mixture_node.dart',
      'engine/src/gaussian_mixture.rs',
    ],
    testFiles: <String>[
      'engine/src/gaussian_mixture.rs',
      'gui/test/gaussian_mixture_test.dart',
    ],
  ),
  'Spectral Features': AlgorithmReview(
    implementation: AlgorithmImplementation.dart,
    summary:
        'Integrates selected frequency-bin power values into conventional bands and derives requested band-power ratios.',
    procedure: <String>[
      'Sum stored spectrum power for bins in delta [0,4), theta [4,8), alpha [8,12), beta [12,40), gamma [40,infinity), or the full range.',
      'Compute requested ratios by dividing the corresponding summed powers.',
      'Write one feature-table row per dataset.',
    ],
    parameters: <String>['Checkboxes select power and ratio columns.'],
    assumptions: <String>[
      'Band power is currently a sum of bins and does not multiply by bin width.',
      'Results inherit the scaling and normalization of the incoming spectrum.',
    ],
    sourceFiles: <String>['gui/lib/nodes/spectral_features_node.dart'],
    testFiles: <String>['gui/test/signal_nodes_test.dart'],
  ),
  'Amplitude Features': AlgorithmReview(
    implementation: AlgorithmImplementation.dart,
    summary:
        'Computes selected scalar features from the primary time-series channel.',
    procedure: <String>[
      'Find the peak sample according to the implementation’s peak rule and report its value and latency.',
      'Compute area under the curve by sample integration divided by sample rate.',
      'Compute population variance around the arithmetic mean.',
      'Write one feature-table row per dataset.',
    ],
    parameters: <String>[
      'Checkboxes select peak amplitude, peak latency, area, and variance.',
    ],
    assumptions: <String>[
      'Only the primary channel is currently analyzed.',
      'Latency is relative to recording start, in milliseconds.',
    ],
    sourceFiles: <String>['gui/lib/nodes/amplitude_features_node.dart'],
    testFiles: <String>['gui/test/signal_nodes_test.dart'],
  ),
  'Python Code': AlgorithmReview(
    implementation: AlgorithmImplementation.external,
    summary:
        'Executes user-supplied Python as an external process. BrainStory validates the declared artifact exchange but does not define or validate the user algorithm itself.',
    procedure: <String>[
      'Serialize the selected upstream artifacts and user parameters to the versioned JSON input contract.',
      'Run the selected Python interpreter and entry point in the configured project directory.',
      'Read the output JSON, validate its protocol version and artifact shapes, then replace downstream artifacts with the declared output.',
    ],
    parameters: <String>[
      'Interpreter, entry point, timeout, source mode, and user-defined JSON parameters.',
    ],
    assumptions: <String>[
      'The user algorithm must be reviewed separately from BrainStory.',
      'Execution is not sandboxed and uses the desktop account’s filesystem and network permissions.',
      'Python execution is unavailable in the browser build.',
    ],
    sourceFiles: <String>[
      'gui/lib/nodes/code_node.dart',
      'gui/lib/nodes/code_contract.dart',
      'gui/lib/platform/code_runner_io.dart',
    ],
    testFiles: <String>['gui/test/code_node_test.dart'],
  ),
};
