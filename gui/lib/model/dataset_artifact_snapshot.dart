import 'data_artifacts.dart';
import 'dataset.dart';

class DatasetArtifactSnapshot {
  const DatasetArtifactSnapshot({
    this.datasetLabel,
    this.timeSeries,
    this.segmentedTimeSeries,
    this.spectrum,
    this.fooofResult,
    this.featureTable,
    this.bridgeDetection,
    this.timeFrequency,
    this.matrixTransformation,
    this.markers,
    this.artifactIdentities =
        const <BrainStoryArtifactKind, ArtifactIdentity>{},
    this.includedKinds,
  });

  final String? datasetLabel;
  final TimeSeriesData? timeSeries;
  final SegmentedTimeSeriesData? segmentedTimeSeries;
  final FrequencySpectrumData? spectrum;
  final FooofResultData? fooofResult;
  final FeatureTableData? featureTable;
  final BridgeDetectionData? bridgeDetection;
  final TimeFrequencyData? timeFrequency;
  final MatrixTransformationData? matrixTransformation;
  final List<TimeMarker>? markers;
  final Map<BrainStoryArtifactKind, ArtifactIdentity> artifactIdentities;
  final Set<BrainStoryArtifactKind>? includedKinds;

  bool ownsKind(BrainStoryArtifactKind kind) {
    return includedKinds?.contains(kind) ?? true;
  }

  bool get isEmpty =>
      timeSeries == null &&
      segmentedTimeSeries == null &&
      spectrum == null &&
      fooofResult == null &&
      featureTable == null &&
      bridgeDetection == null &&
      timeFrequency == null &&
      matrixTransformation == null &&
      markers == null &&
      artifactIdentities.isEmpty;

  factory DatasetArtifactSnapshot.fromDataset(
    Dataset dataset, {
    Set<BrainStoryArtifactKind>? includedKinds,
  }) {
    final Set<BrainStoryArtifactKind>? kinds = includedKinds == null
        ? null
        : Set<BrainStoryArtifactKind>.from(includedKinds);
    return DatasetArtifactSnapshot(
      datasetLabel: dataset.label,
      timeSeries:
          (kinds != null &&
                  !kinds.contains(BrainStoryArtifactKind.timeSeries)) ||
              dataset.timeSeries == null
          ? null
          : TimeSeriesData.fromJson(dataset.timeSeries!.toJson()),
      segmentedTimeSeries:
          (kinds != null &&
                  !kinds.contains(
                    BrainStoryArtifactKind.segmentedTimeSeries,
                  )) ||
              dataset.segmentedTimeSeries == null
          ? null
          : SegmentedTimeSeriesData.fromJson(
              dataset.segmentedTimeSeries!.toJson(),
            ),
      spectrum:
          (kinds != null && !kinds.contains(BrainStoryArtifactKind.spectrum)) ||
              dataset.spectrum == null
          ? null
          : FrequencySpectrumData.fromJson(dataset.spectrum!.toJson()),
      fooofResult:
          (kinds != null &&
                  !kinds.contains(BrainStoryArtifactKind.fooofResult)) ||
              dataset.fooofResult == null
          ? null
          : FooofResultData.fromJson(dataset.fooofResult!.toJson()),
      featureTable:
          (kinds != null &&
                  !kinds.contains(BrainStoryArtifactKind.featureTable)) ||
              dataset.featureTable == null
          ? null
          : FeatureTableData.fromJson(dataset.featureTable!.toJson()),
      bridgeDetection:
          (kinds != null &&
                  !kinds.contains(BrainStoryArtifactKind.bridgeDetection)) ||
              dataset.bridgeDetection == null
          ? null
          : BridgeDetectionData.fromJson(dataset.bridgeDetection!.toJson()),
      timeFrequency:
          (kinds != null &&
                  !kinds.contains(BrainStoryArtifactKind.timeFrequency)) ||
              dataset.timeFrequency == null
          ? null
          : TimeFrequencyData.fromJson(dataset.timeFrequency!.toJson()),
      matrixTransformation:
          (kinds != null &&
                  !kinds.contains(
                    BrainStoryArtifactKind.matrixTransformation,
                  )) ||
              dataset.matrixTransformation == null
          ? null
          : MatrixTransformationData.fromJson(
              dataset.matrixTransformation!.toJson(),
            ),
      markers: (kinds != null && kinds.contains(BrainStoryArtifactKind.markers))
          ? List<TimeMarker>.from(
              dataset.timeSeries?.markers ?? const <TimeMarker>[],
            )
          : null,
      artifactIdentities: kinds == null
          ? dataset.artifactIdentities
          : Map<BrainStoryArtifactKind, ArtifactIdentity>.fromEntries(
              dataset.artifactIdentities.entries.where(
                (MapEntry<BrainStoryArtifactKind, ArtifactIdentity> entry) =>
                    kinds.contains(entry.key),
              ),
            ),
      includedKinds: kinds,
    );
  }

  void applyToDataset(Dataset dataset) {
    if (datasetLabel != null) {
      dataset.label = datasetLabel!;
    }
    if (ownsKind(BrainStoryArtifactKind.timeSeries)) {
      dataset.timeSeries = timeSeries == null
          ? null
          : TimeSeriesData.fromJson(timeSeries!.toJson());
    }
    if (ownsKind(BrainStoryArtifactKind.segmentedTimeSeries)) {
      dataset.segmentedTimeSeries = segmentedTimeSeries == null
          ? null
          : SegmentedTimeSeriesData.fromJson(segmentedTimeSeries!.toJson());
    }
    if (ownsKind(BrainStoryArtifactKind.spectrum)) {
      dataset.spectrum = spectrum == null
          ? null
          : FrequencySpectrumData.fromJson(spectrum!.toJson());
    }
    if (ownsKind(BrainStoryArtifactKind.fooofResult)) {
      dataset.fooofResult = fooofResult == null
          ? null
          : FooofResultData.fromJson(fooofResult!.toJson());
    }
    if (ownsKind(BrainStoryArtifactKind.featureTable)) {
      dataset.featureTable = featureTable == null
          ? null
          : FeatureTableData.fromJson(featureTable!.toJson());
    }
    if (ownsKind(BrainStoryArtifactKind.bridgeDetection)) {
      dataset.bridgeDetection = bridgeDetection == null
          ? null
          : BridgeDetectionData.fromJson(bridgeDetection!.toJson());
    }
    if (ownsKind(BrainStoryArtifactKind.timeFrequency)) {
      dataset.timeFrequency = timeFrequency == null
          ? null
          : TimeFrequencyData.fromJson(timeFrequency!.toJson());
    }
    if (ownsKind(BrainStoryArtifactKind.matrixTransformation)) {
      dataset.matrixTransformation = matrixTransformation == null
          ? null
          : MatrixTransformationData.fromJson(matrixTransformation!.toJson());
    }
    if (ownsKind(BrainStoryArtifactKind.markers) && markers != null) {
      final TimeSeriesData? timeSeries = dataset.timeSeries;
      if (timeSeries != null) {
        dataset.timeSeries = timeSeries.copyWith(
          markers: markers!
              .map((TimeMarker marker) => TimeMarker.fromJson(marker.toJson()))
              .toList(growable: false),
        );
      }
    }
    if (includedKinds == null) {
      dataset.artifactIdentities = artifactIdentities;
    } else {
      final Map<BrainStoryArtifactKind, ArtifactIdentity> nextIdentities =
          Map<BrainStoryArtifactKind, ArtifactIdentity>.from(
            dataset.artifactIdentities,
          );
      for (final BrainStoryArtifactKind kind in includedKinds!) {
        final ArtifactIdentity? identity = artifactIdentities[kind];
        if (identity == null) {
          nextIdentities.remove(kind);
        } else {
          nextIdentities[kind] = identity;
        }
      }
      dataset.artifactIdentities = nextIdentities;
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (datasetLabel != null) 'datasetLabel': datasetLabel,
      if (timeSeries != null) 'timeSeries': timeSeries!.toJson(),
      if (segmentedTimeSeries != null)
        'segmentedTimeSeries': segmentedTimeSeries!.toJson(),
      if (spectrum != null) 'spectrum': spectrum!.toJson(),
      if (fooofResult != null) 'fooofResult': fooofResult!.toJson(),
      if (featureTable != null) 'featureTable': featureTable!.toJson(),
      if (bridgeDetection != null) 'bridgeDetection': bridgeDetection!.toJson(),
      if (timeFrequency != null) 'timeFrequency': timeFrequency!.toJson(),
      if (matrixTransformation != null)
        'matrixTransformation': matrixTransformation!.toJson(),
      if (markers != null)
        'markers': markers!
            .map((TimeMarker marker) => marker.toJson())
            .toList(),
      if (artifactIdentities.isNotEmpty)
        'artifactIdentities': artifactIdentities.map(
          (BrainStoryArtifactKind key, ArtifactIdentity value) =>
              MapEntry<String, dynamic>(key.name, value.toJson()),
        ),
      if (includedKinds != null)
        'includedKinds': includedKinds!
            .map((BrainStoryArtifactKind kind) => kind.name)
            .toList(),
    };
  }

  static DatasetArtifactSnapshot fromJson(Map<String, dynamic> json) {
    return DatasetArtifactSnapshot(
      datasetLabel: json['datasetLabel']?.toString(),
      timeSeries: json['timeSeries'] is Map<String, dynamic>
          ? TimeSeriesData.fromJson(json['timeSeries'] as Map<String, dynamic>)
          : null,
      segmentedTimeSeries: json['segmentedTimeSeries'] is Map<String, dynamic>
          ? SegmentedTimeSeriesData.fromJson(
              json['segmentedTimeSeries'] as Map<String, dynamic>,
            )
          : null,
      spectrum: json['spectrum'] is Map<String, dynamic>
          ? FrequencySpectrumData.fromJson(
              json['spectrum'] as Map<String, dynamic>,
            )
          : null,
      fooofResult: json['fooofResult'] is Map<String, dynamic>
          ? FooofResultData.fromJson(
              json['fooofResult'] as Map<String, dynamic>,
            )
          : null,
      featureTable: json['featureTable'] is Map<String, dynamic>
          ? FeatureTableData.fromJson(
              json['featureTable'] as Map<String, dynamic>,
            )
          : null,
      bridgeDetection: json['bridgeDetection'] is Map<String, dynamic>
          ? BridgeDetectionData.fromJson(
              json['bridgeDetection'] as Map<String, dynamic>,
            )
          : null,
      timeFrequency: json['timeFrequency'] is Map<String, dynamic>
          ? TimeFrequencyData.fromJson(
              json['timeFrequency'] as Map<String, dynamic>,
            )
          : null,
      matrixTransformation: json['matrixTransformation'] is Map<String, dynamic>
          ? MatrixTransformationData.fromJson(
              json['matrixTransformation'] as Map<String, dynamic>,
            )
          : null,
      markers: json['markers'] is List
          ? (json['markers'] as List<dynamic>)
                .map(
                  (dynamic value) => TimeMarker.fromJson(
                    Map<String, dynamic>.from(
                      value as Map? ?? const <String, dynamic>{},
                    ),
                  ),
                )
                .toList(growable: false)
          : null,
      artifactIdentities:
          (json['artifactIdentities'] as Map? ?? const <String, dynamic>{})
              .map<BrainStoryArtifactKind, ArtifactIdentity>((
                dynamic key,
                dynamic value,
              ) {
                return MapEntry<BrainStoryArtifactKind, ArtifactIdentity>(
                  artifactKindFromWireValue(key.toString()),
                  ArtifactIdentity.fromJson(
                    Map<String, dynamic>.from(
                      value as Map? ?? const <String, dynamic>{},
                    ),
                  ),
                );
              }),
      includedKinds: json['includedKinds'] is List
          ? (json['includedKinds'] as List<dynamic>)
                .map(
                  (dynamic value) =>
                      artifactKindFromWireValue(value.toString()),
                )
                .toSet()
          : null,
    );
  }

  DatasetArtifactSnapshot withDatasetLabel(String label) {
    return DatasetArtifactSnapshot(
      datasetLabel: label,
      timeSeries: timeSeries,
      segmentedTimeSeries: segmentedTimeSeries,
      spectrum: spectrum,
      fooofResult: fooofResult,
      featureTable: featureTable,
      bridgeDetection: bridgeDetection,
      timeFrequency: timeFrequency,
      matrixTransformation: matrixTransformation,
      markers: markers,
      artifactIdentities: artifactIdentities,
      includedKinds: includedKinds,
    );
  }
}
