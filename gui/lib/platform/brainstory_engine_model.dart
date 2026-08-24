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
