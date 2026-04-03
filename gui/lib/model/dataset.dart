import 'dart:typed_data';

import 'data_artifacts.dart';

class Dataset {
  final String id;
  String label;
  String path;
  Uint8List? sourceBytes;

  bool loaded = false;

  /// In-memory artifacts (temporary, per-dataset)
  /// Keys like: 'signal.samples', 'signal.fs', 'psd.freqs', 'psd.power'
  final Map<String, dynamic> ram = {};

  Dataset(
      this.id, {
        this.label = '',
        this.path = '',
        this.sourceBytes,
      });

  TimeSeriesData? get timeSeries =>
      ram['artifact.timeSeries'] as TimeSeriesData?;
  set timeSeries(TimeSeriesData? value) {
    if (value == null) {
      ram.remove('artifact.timeSeries');
      ram.remove('signal.samples');
      ram.remove('signal.channels');
      ram.remove('signal.fs');
      ram.remove('signal.channelLabels');
      ram.remove('signal.markers');
      ram.remove('signal.factors');
      ram.remove('signal.source');
      return;
    }
    ram['artifact.timeSeries'] = value;
    ram['signal.samples'] = value.primaryChannel;
    ram['signal.channels'] = value.channels;
    ram['signal.fs'] = value.sampleRate;
    ram['signal.channelLabels'] = value.channelLabels;
    ram['signal.markers'] = value.markers.map((TimeMarker marker) => marker.toJson()).toList();
    ram['signal.factors'] =
        value.factors.map((Factor factor) => factor.toJson()).toList();
    ram['signal.source'] = value.source;
  }

  FrequencySpectrumData? get spectrum =>
      ram['artifact.spectrum'] as FrequencySpectrumData?;
  set spectrum(FrequencySpectrumData? value) {
    if (value == null) {
      ram.remove('artifact.spectrum');
      ram.remove('psd.freqs');
      ram.remove('psd.power');
      ram.remove('psd.segmentCount');
      return;
    }
    ram['artifact.spectrum'] = value;
    ram['psd.freqs'] = value.frequencies;
    ram['psd.power'] = value.power;
    ram['psd.segmentCount'] = value.segmentCount;
  }

  FooofResultData? get fooofResult =>
      ram['artifact.fooofResult'] as FooofResultData?;
  set fooofResult(FooofResultData? value) {
    if (value == null) {
      ram.remove('artifact.fooofResult');
      ram.remove('fooof.intercept');
      ram.remove('fooof.exponent');
      ram.remove('fooof.peaks');
      return;
    }
    ram['artifact.fooofResult'] = value;
    ram['fooof.intercept'] = value.intercept;
    ram['fooof.exponent'] = value.exponent;
    ram['fooof.peaks'] =
        value.peaks.map((FooofPeakData peak) => peak.toJson()).toList(growable: false);
  }

  FeatureTableData? get featureTable =>
      ram['artifact.featureTable'] as FeatureTableData?;
  set featureTable(FeatureTableData? value) {
    if (value == null) {
      ram.remove('artifact.featureTable');
      ram.remove('featureTable.columns');
      ram.remove('featureTable.rows');
      ram.remove('featureTable.csv');
      return;
    }
    ram['artifact.featureTable'] = value;
    ram['featureTable.columns'] = value.columns;
    ram['featureTable.rows'] = value.rows;
    ram['featureTable.csv'] = value.toCsv();
  }

  BridgeDetectionData? get bridgeDetection =>
      ram['artifact.bridgeDetection'] as BridgeDetectionData?;
  set bridgeDetection(BridgeDetectionData? value) {
    if (value == null) {
      ram.remove('artifact.bridgeDetection');
      ram.remove('bridgeDetection.windowSampleCount');
      ram.remove('bridgeDetection.frameCount');
      ram.remove('bridgeDetection.valueCount');
      return;
    }
    ram['artifact.bridgeDetection'] = value;
    ram['bridgeDetection.windowSampleCount'] = value.windowSampleCount;
    ram['bridgeDetection.frameCount'] = value.frameCount;
    ram['bridgeDetection.valueCount'] = value.valueCount;
  }

  SegmentedTimeSeriesData? get segmentedTimeSeries =>
      ram['artifact.segmentedTimeSeries'] as SegmentedTimeSeriesData?;
  set segmentedTimeSeries(SegmentedTimeSeriesData? value) {
    if (value == null) {
      ram.remove('artifact.segmentedTimeSeries');
      ram.remove('segments.count');
      ram.remove('segments.sampleRate');
      ram.remove('segments.channelLabels');
      ram.remove('segments.source');
      return;
    }
    ram['artifact.segmentedTimeSeries'] = value;
    ram['segments.count'] = value.segmentCount;
    ram['segments.sampleRate'] = value.sampleRate;
    ram['segments.channelLabels'] = value.channelLabels;
    ram['segments.source'] = value.source;
  }

  TimeFrequencyData? get timeFrequency =>
      ram['artifact.timeFrequency'] as TimeFrequencyData?;
  set timeFrequency(TimeFrequencyData? value) {
    if (value == null) {
      ram.remove('artifact.timeFrequency');
      return;
    }
    ram['artifact.timeFrequency'] = value;
  }

  MatrixTransformationData? get matrixTransformation =>
      ram['artifact.matrixTransformation'] as MatrixTransformationData?;
  set matrixTransformation(MatrixTransformationData? value) {
    if (value == null) {
      ram.remove('artifact.matrixTransformation');
      return;
    }
    ram['artifact.matrixTransformation'] = value;
  }
}
