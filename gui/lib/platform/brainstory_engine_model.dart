class AggregateSeriesStats {
  const AggregateSeriesStats({
    required this.mean,
    required this.standardDeviation,
  });

  final List<double> mean;
  final List<double> standardDeviation;
}

class NativeSpectrumResult {
  const NativeSpectrumResult({required this.frequencies, required this.power});

  final List<double> frequencies;
  final List<double> power;
}

class NativeWaveletResult {
  const NativeWaveletResult({
    required this.times,
    required this.frequencies,
    required this.powerMatrix,
  });

  final List<double> times;
  final List<double> frequencies;
  final List<List<double>> powerMatrix;

  factory NativeWaveletResult.fromJson(Map<String, dynamic> json) {
    List<double> vector(dynamic value) {
      return (value as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic item) => (item as num).toDouble())
          .toList(growable: false);
    }

    return NativeWaveletResult(
      times: vector(json['times']),
      frequencies: vector(json['frequencies']),
      powerMatrix: (json['powerMatrix'] as List<dynamic>? ?? const <dynamic>[])
          .map(vector)
          .toList(growable: false),
    );
  }
}

class NativeGaussianMixtureResult {
  const NativeGaussianMixtureResult({
    required this.assignments,
    required this.probabilities,
    required this.weights,
    required this.means,
    required this.variances,
    required this.converged,
    required this.iterationCount,
    required this.logLikelihood,
    required this.aic,
    required this.bic,
    required this.normalizationMean,
    required this.normalizationScale,
  });

  final List<int> assignments;
  final List<List<double>> probabilities;
  final List<double> weights;
  final List<List<double>> means;
  final List<List<double>> variances;
  final bool converged;
  final int iterationCount;
  final double logLikelihood;
  final double aic;
  final double bic;
  final List<double> normalizationMean;
  final List<double> normalizationScale;

  factory NativeGaussianMixtureResult.fromJson(Map<String, dynamic> json) {
    List<double> vector(dynamic value) =>
        (value as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic item) => (item as num).toDouble())
            .toList(growable: false);
    List<List<double>> matrix(dynamic value) =>
        (value as List<dynamic>? ?? const <dynamic>[])
            .map(vector)
            .toList(growable: false);

    return NativeGaussianMixtureResult(
      assignments: (json['assignments'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toInt())
          .toList(growable: false),
      probabilities: matrix(json['probabilities']),
      weights: vector(json['weights']),
      means: matrix(json['means']),
      variances: matrix(json['variances']),
      converged: json['converged'] == true,
      iterationCount: (json['iterationCount'] as num?)?.toInt() ?? 0,
      logLikelihood: (json['logLikelihood'] as num?)?.toDouble() ?? 0.0,
      aic: (json['aic'] as num?)?.toDouble() ?? 0.0,
      bic: (json['bic'] as num?)?.toDouble() ?? 0.0,
      normalizationMean: vector(json['normalizationMean']),
      normalizationScale: vector(json['normalizationScale']),
    );
  }
}

class NativeIcaResult {
  const NativeIcaResult({
    required this.activations,
    required this.unmixingMatrix,
    required this.mixingMatrix,
    required this.whiteningMatrix,
    required this.dewhiteningMatrix,
    required this.channelMeans,
    required this.componentEnergies,
    required this.converged,
    required this.iterationCount,
    required this.numericalRank,
    required this.tolerance,
    required this.maxIterations,
    required this.seed,
  });

  final List<List<double>> activations;
  final List<List<double>> unmixingMatrix;
  final List<List<double>> mixingMatrix;
  final List<List<double>> whiteningMatrix;
  final List<List<double>> dewhiteningMatrix;
  final List<double> channelMeans;
  final List<double> componentEnergies;
  final bool converged;
  final int iterationCount;
  final int numericalRank;
  final double tolerance;
  final int maxIterations;
  final int seed;

  factory NativeIcaResult.fromJson(Map<String, dynamic> json) {
    List<List<double>> matrix(String key) {
      return (json[key] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic row) => (row as List<dynamic>)
                .map((dynamic value) => (value as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false);
    }

    List<double> vector(String key) {
      return (json[key] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => (value as num).toDouble())
          .toList(growable: false);
    }

    return NativeIcaResult(
      activations: matrix('activations'),
      unmixingMatrix: matrix('unmixingMatrix'),
      mixingMatrix: matrix('mixingMatrix'),
      whiteningMatrix: matrix('whiteningMatrix'),
      dewhiteningMatrix: matrix('dewhiteningMatrix'),
      channelMeans: vector('channelMeans'),
      componentEnergies: vector('componentEnergies'),
      converged: json['converged'] == true,
      iterationCount: (json['iterationCount'] as num?)?.toInt() ?? 0,
      numericalRank: (json['numericalRank'] as num?)?.toInt() ?? 0,
      tolerance: (json['tolerance'] as num?)?.toDouble() ?? 0.0,
      maxIterations: (json['maxIterations'] as num?)?.toInt() ?? 0,
      seed: (json['seed'] as num?)?.toInt() ?? 0,
    );
  }
}
