import 'data_artifacts.dart';
import 'dataset.dart';

class DatasetArtifactSnapshot {
  const DatasetArtifactSnapshot({
    this.timeSeries,
    this.segmentedTimeSeries,
    this.spectrum,
    this.timeFrequency,
    this.matrixTransformation,
  });

  final TimeSeriesData? timeSeries;
  final SegmentedTimeSeriesData? segmentedTimeSeries;
  final FrequencySpectrumData? spectrum;
  final TimeFrequencyData? timeFrequency;
  final MatrixTransformationData? matrixTransformation;

  bool get isEmpty =>
      timeSeries == null &&
      segmentedTimeSeries == null &&
      spectrum == null &&
      timeFrequency == null &&
      matrixTransformation == null;

  factory DatasetArtifactSnapshot.fromDataset(Dataset dataset) {
    return DatasetArtifactSnapshot(
      timeSeries: dataset.timeSeries == null
          ? null
          : TimeSeriesData.fromJson(dataset.timeSeries!.toJson()),
      segmentedTimeSeries: dataset.segmentedTimeSeries == null
          ? null
          : SegmentedTimeSeriesData.fromJson(
              dataset.segmentedTimeSeries!.toJson(),
            ),
      spectrum: dataset.spectrum == null
          ? null
          : FrequencySpectrumData.fromJson(dataset.spectrum!.toJson()),
      timeFrequency: dataset.timeFrequency == null
          ? null
          : TimeFrequencyData.fromJson(dataset.timeFrequency!.toJson()),
      matrixTransformation: dataset.matrixTransformation == null
          ? null
          : MatrixTransformationData.fromJson(
              dataset.matrixTransformation!.toJson(),
            ),
    );
  }

  void applyToDataset(Dataset dataset) {
    dataset.timeSeries = timeSeries == null
        ? null
        : TimeSeriesData.fromJson(timeSeries!.toJson());
    dataset.segmentedTimeSeries = segmentedTimeSeries == null
        ? null
        : SegmentedTimeSeriesData.fromJson(segmentedTimeSeries!.toJson());
    dataset.spectrum = spectrum == null
        ? null
        : FrequencySpectrumData.fromJson(spectrum!.toJson());
    dataset.timeFrequency = timeFrequency == null
        ? null
        : TimeFrequencyData.fromJson(timeFrequency!.toJson());
    dataset.matrixTransformation = matrixTransformation == null
        ? null
        : MatrixTransformationData.fromJson(matrixTransformation!.toJson());
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (timeSeries != null) 'timeSeries': timeSeries!.toJson(),
      if (segmentedTimeSeries != null)
        'segmentedTimeSeries': segmentedTimeSeries!.toJson(),
      if (spectrum != null) 'spectrum': spectrum!.toJson(),
      if (timeFrequency != null) 'timeFrequency': timeFrequency!.toJson(),
      if (matrixTransformation != null)
        'matrixTransformation': matrixTransformation!.toJson(),
    };
  }

  static DatasetArtifactSnapshot fromJson(Map<String, dynamic> json) {
    return DatasetArtifactSnapshot(
      timeSeries: json['timeSeries'] is Map<String, dynamic>
          ? TimeSeriesData.fromJson(json['timeSeries'] as Map<String, dynamic>)
          : null,
      segmentedTimeSeries: json['segmentedTimeSeries'] is Map<String, dynamic>
          ? SegmentedTimeSeriesData.fromJson(
              json['segmentedTimeSeries'] as Map<String, dynamic>,
            )
          : null,
      spectrum: json['spectrum'] is Map<String, dynamic>
          ? FrequencySpectrumData.fromJson(json['spectrum'] as Map<String, dynamic>)
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
    );
  }
}
