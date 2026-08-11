import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'brainstory_engine_model.dart';

typedef _SegmentMeanSdNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Double> traces,
      ffi.IntPtr traceCount,
      ffi.IntPtr sampleCount,
      ffi.Pointer<ffi.Double> meanOut,
      ffi.Pointer<ffi.Double> sdOut,
    );
typedef _SegmentMeanSdDart =
    int Function(
      ffi.Pointer<ffi.Double> traces,
      int traceCount,
      int sampleCount,
      ffi.Pointer<ffi.Double> meanOut,
      ffi.Pointer<ffi.Double> sdOut,
    );

typedef _BandpassFilterNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Double> input,
      ffi.IntPtr sampleCount,
      ffi.Double sampleRate,
      ffi.Double lowCutHz,
      ffi.Double highCutHz,
      ffi.Double steepness,
      ffi.Double notchHz,
      ffi.Pointer<ffi.Double> output,
    );
typedef _BandpassFilterDart =
    int Function(
      ffi.Pointer<ffi.Double> input,
      int sampleCount,
      double sampleRate,
      double lowCutHz,
      double highCutHz,
      double steepness,
      double notchHz,
      ffi.Pointer<ffi.Double> output,
    );

typedef _SingleSidedSpectrumNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Double> samples,
      ffi.IntPtr sampleCount,
      ffi.Double sampleRate,
      ffi.Double lowHz,
      ffi.Double highHz,
      ffi.Pointer<ffi.Double> frequenciesOut,
      ffi.Pointer<ffi.Double> powerOut,
      ffi.IntPtr outputCapacity,
      ffi.Pointer<ffi.IntPtr> binCountOut,
    );
typedef _SingleSidedSpectrumDart =
    int Function(
      ffi.Pointer<ffi.Double> samples,
      int sampleCount,
      double sampleRate,
      double lowHz,
      double highHz,
      ffi.Pointer<ffi.Double> frequenciesOut,
      ffi.Pointer<ffi.Double> powerOut,
      int outputCapacity,
      ffi.Pointer<ffi.IntPtr> binCountOut,
    );

typedef _CallocNative =
    ffi.Pointer<ffi.Void> Function(ffi.IntPtr itemCount, ffi.IntPtr itemSize);
typedef _CallocDart =
    ffi.Pointer<ffi.Void> Function(int itemCount, int itemSize);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void> pointer);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void> pointer);

typedef _AntCntImportNative =
    ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Uint8> path);
typedef _AntCntImportDart =
    ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Uint8> path);

typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<ffi.Uint8> pointer);
typedef _FreeStringDart = void Function(ffi.Pointer<ffi.Uint8> pointer);

final _BrainstoryEngineLibrary _engineLibrary = _BrainstoryEngineLibrary();
final _NativeMemory _nativeMemory = _NativeMemory();

NativeSpectrumResult? computeSingleSidedSpectrumNative(
  List<double> samples, {
  required double sampleRate,
  required double lowHz,
  required double highHz,
}) {
  if (samples.isEmpty) {
    return const NativeSpectrumResult(
      frequencies: <double>[],
      power: <double>[],
    );
  }
  final _SingleSidedSpectrumDart? spectrumFunction =
      _engineLibrary.singleSidedSpectrum;
  if (spectrumFunction == null || _nativeMemory.unavailable) {
    return null;
  }

  final int capacity = (samples.length ~/ 2) + 1;
  final ffi.Pointer<ffi.Double> samplesPtr = _nativeMemory.callocDouble(
    samples.length,
  );
  final ffi.Pointer<ffi.Double> frequenciesPtr = _nativeMemory.callocDouble(
    capacity,
  );
  final ffi.Pointer<ffi.Double> powerPtr = _nativeMemory.callocDouble(capacity);
  final ffi.Pointer<ffi.IntPtr> binCountPtr = _nativeMemory.callocIntPtr();
  try {
    for (int index = 0; index < samples.length; index++) {
      samplesPtr[index] = samples[index];
    }
    final int status = spectrumFunction(
      samplesPtr,
      samples.length,
      sampleRate,
      lowHz,
      highHz,
      frequenciesPtr,
      powerPtr,
      capacity,
      binCountPtr,
    );
    final int binCount = binCountPtr.value;
    if (status != 0 || binCount < 0 || binCount > capacity) {
      return null;
    }
    return NativeSpectrumResult(
      frequencies: List<double>.generate(
        binCount,
        (int index) => frequenciesPtr[index],
        growable: false,
      ),
      power: List<double>.generate(
        binCount,
        (int index) => powerPtr[index],
        growable: false,
      ),
    );
  } finally {
    _nativeMemory.free(samplesPtr.cast<ffi.Void>());
    _nativeMemory.free(frequenciesPtr.cast<ffi.Void>());
    _nativeMemory.free(powerPtr.cast<ffi.Void>());
    _nativeMemory.free(binCountPtr.cast<ffi.Void>());
  }
}

List<double>? applyBandpassFilterNative(
  List<double> input, {
  required double sampleRate,
  required double lowCutHz,
  required double highCutHz,
  required double steepness,
  double? notchHz,
}) {
  if (input.isEmpty) {
    return <double>[];
  }
  final _BandpassFilterDart? filter = _engineLibrary.bandpassFilter;
  if (filter == null || _nativeMemory.unavailable) {
    return null;
  }

  final ffi.Pointer<ffi.Double> inputPtr = _nativeMemory.callocDouble(
    input.length,
  );
  final ffi.Pointer<ffi.Double> outputPtr = _nativeMemory.callocDouble(
    input.length,
  );
  try {
    for (int index = 0; index < input.length; index++) {
      inputPtr[index] = input[index];
    }
    final int status = filter(
      inputPtr,
      input.length,
      sampleRate,
      lowCutHz,
      highCutHz,
      steepness,
      notchHz ?? double.nan,
      outputPtr,
    );
    if (status != 0) {
      return null;
    }
    return List<double>.generate(
      input.length,
      (int index) => outputPtr[index],
      growable: false,
    );
  } finally {
    _nativeMemory.free(inputPtr.cast<ffi.Void>());
    _nativeMemory.free(outputPtr.cast<ffi.Void>());
  }
}

String? readAntCntPayloadNative(String path) {
  final _AntCntImportDart? importer = _engineLibrary.antCntImport;
  if (importer == null || _nativeMemory.unavailable) {
    return null;
  }
  final List<int> encodedPath = utf8.encode(path);
  final ffi.Pointer<ffi.Uint8> pathPointer = _nativeMemory.callocBytes(
    encodedPath.length + 1,
  );
  try {
    pathPointer.asTypedList(encodedPath.length).setAll(0, encodedPath);
    final ffi.Pointer<ffi.Uint8> result = importer(pathPointer);
    if (result == ffi.nullptr) {
      return null;
    }
    try {
      final List<int> bytes = <int>[];
      for (int index = 0; result[index] != 0; index++) {
        bytes.add(result[index]);
      }
      return utf8.decode(bytes);
    } finally {
      _engineLibrary.freeString(result);
    }
  } finally {
    _nativeMemory.free(pathPointer.cast<ffi.Void>());
  }
}

AggregateSeriesStats? computeAggregateSeriesStats(List<List<double>> traces) {
  if (traces.isEmpty) {
    return null;
  }
  final int sampleCount = traces.first.length;
  if (sampleCount == 0 ||
      traces.any((List<double> trace) => trace.length != sampleCount)) {
    return null;
  }

  final _SegmentMeanSdDart? segmentMeanSd = _engineLibrary.segmentMeanSd;
  if (segmentMeanSd == null || _nativeMemory.unavailable) {
    return null;
  }

  final int traceCount = traces.length;
  final ffi.Pointer<ffi.Double> tracePtr = _nativeMemory.callocDouble(
    traceCount * sampleCount,
  );
  final ffi.Pointer<ffi.Double> meanPtr = _nativeMemory.callocDouble(
    sampleCount,
  );
  final ffi.Pointer<ffi.Double> sdPtr = _nativeMemory.callocDouble(sampleCount);

  try {
    int flatIndex = 0;
    for (final List<double> trace in traces) {
      for (final double value in trace) {
        tracePtr[flatIndex] = value;
        flatIndex++;
      }
    }

    final int status = segmentMeanSd(
      tracePtr,
      traceCount,
      sampleCount,
      meanPtr,
      sdPtr,
    );
    if (status != 0) {
      return null;
    }

    return AggregateSeriesStats(
      mean: List<double>.generate(
        sampleCount,
        (int index) => meanPtr[index],
        growable: false,
      ),
      standardDeviation: List<double>.generate(
        sampleCount,
        (int index) => sdPtr[index],
        growable: false,
      ),
    );
  } finally {
    _nativeMemory.free(tracePtr.cast<ffi.Void>());
    _nativeMemory.free(meanPtr.cast<ffi.Void>());
    _nativeMemory.free(sdPtr.cast<ffi.Void>());
  }
}

class _BrainstoryEngineLibrary {
  _BrainstoryEngineLibrary() : _library = _tryLoadLibrary();

  final ffi.DynamicLibrary? _library;

  _SingleSidedSpectrumDart? get singleSidedSpectrum {
    final ffi.DynamicLibrary? library = _library;
    if (library == null) {
      return null;
    }
    try {
      return library
          .lookupFunction<_SingleSidedSpectrumNative, _SingleSidedSpectrumDart>(
            'brainstory_single_sided_spectrum',
          );
    } catch (_) {
      return null;
    }
  }

  _BandpassFilterDart? get bandpassFilter {
    final ffi.DynamicLibrary? library = _library;
    if (library == null) {
      return null;
    }
    return library.lookupFunction<_BandpassFilterNative, _BandpassFilterDart>(
      'brainstory_bandpass_filter',
    );
  }

  _SegmentMeanSdDart? get segmentMeanSd {
    final ffi.DynamicLibrary? library = _library;
    if (library == null) {
      return null;
    }
    return library.lookupFunction<_SegmentMeanSdNative, _SegmentMeanSdDart>(
      'brainstory_segment_mean_sd',
    );
  }

  _AntCntImportDart? get antCntImport {
    final ffi.DynamicLibrary? library = _library;
    if (library == null) {
      return null;
    }
    try {
      return library.lookupFunction<_AntCntImportNative, _AntCntImportDart>(
        'brainstory_ant_cnt_import',
      );
    } catch (_) {
      return null;
    }
  }

  void freeString(ffi.Pointer<ffi.Uint8> pointer) {
    final ffi.DynamicLibrary? library = _library;
    if (library == null) {
      return;
    }
    try {
      final _FreeStringDart free = library
          .lookupFunction<_FreeStringNative, _FreeStringDart>(
            'brainstory_engine_free_string',
          );
      free(pointer);
    } catch (_) {
      // The engine returns an allocated error string only when the matching
      // free function is available in the same library.
    }
  }

  static ffi.DynamicLibrary? _tryLoadLibrary() {
    final String libraryName = Platform.isWindows
        ? 'brainstory_engine.dll'
        : Platform.isMacOS
        ? 'libbrainstory_engine.dylib'
        : 'libbrainstory_engine.so';
    final Directory executableDirectory = File(
      Platform.resolvedExecutable,
    ).parent;
    final String bundledLibraryPath = Platform.isMacOS
        ? _join(
            _join(executableDirectory.parent.path, 'Frameworks'),
            libraryName,
          )
        : Platform.isLinux
        ? _join(_join(executableDirectory.path, 'lib'), libraryName)
        : _join(executableDirectory.path, libraryName);
    final Set<String> candidates = <String>{
      libraryName,
      bundledLibraryPath,
      _join(executableDirectory.path, libraryName),
      _join(Directory.current.path, libraryName),
      _join(Directory.current.path, '../engine/target/debug/$libraryName'),
      _join(Directory.current.path, '../engine/target/release/$libraryName'),
      _join(Directory.current.path, 'engine/target/debug/$libraryName'),
      _join(Directory.current.path, 'engine/target/release/$libraryName'),
    };

    for (final String candidate in candidates) {
      try {
        if (candidate == libraryName || File(candidate).existsSync()) {
          return ffi.DynamicLibrary.open(candidate);
        }
      } catch (_) {
        // Fall through to the next candidate path and use the Dart fallback
        // if the engine library is unavailable.
      }
    }
    return null;
  }

  static String _join(String base, String leaf) {
    final String normalizedBase = base.endsWith('\\') || base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalizedBase${Platform.pathSeparator}$leaf';
  }
}

class _NativeMemory {
  _NativeMemory() : _library = _tryLoadLibrary();

  final ffi.DynamicLibrary? _library;

  bool get unavailable => _library == null;

  ffi.Pointer<ffi.Double> callocDouble(int count) {
    final _CallocDart callocFn = _calloc;
    return callocFn(count, ffi.sizeOf<ffi.Double>()).cast<ffi.Double>();
  }

  ffi.Pointer<ffi.Uint8> callocBytes(int count) {
    return _calloc(count, ffi.sizeOf<ffi.Uint8>()).cast<ffi.Uint8>();
  }

  ffi.Pointer<ffi.IntPtr> callocIntPtr() {
    return _calloc(1, ffi.sizeOf<ffi.IntPtr>()).cast<ffi.IntPtr>();
  }

  void free(ffi.Pointer<ffi.Void> pointer) {
    _free(pointer);
  }

  _CallocDart get _calloc =>
      _library!.lookupFunction<_CallocNative, _CallocDart>('calloc');

  _FreeDart get _free =>
      _library!.lookupFunction<_FreeNative, _FreeDart>('free');

  static ffi.DynamicLibrary? _tryLoadLibrary() {
    if (!Platform.isWindows) {
      return ffi.DynamicLibrary.process();
    }
    for (final String libraryName in <String>['ucrtbase.dll', 'msvcrt.dll']) {
      try {
        return ffi.DynamicLibrary.open(libraryName);
      } catch (_) {
        // Try the next CRT name.
      }
    }
    return null;
  }
}
