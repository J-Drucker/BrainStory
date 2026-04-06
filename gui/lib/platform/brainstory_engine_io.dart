import 'dart:ffi' as ffi;
import 'dart:io';

import 'brainstory_engine_model.dart';

typedef _SegmentMeanSdNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Double> traces,
  ffi.IntPtr traceCount,
  ffi.IntPtr sampleCount,
  ffi.Pointer<ffi.Double> meanOut,
  ffi.Pointer<ffi.Double> sdOut,
);
typedef _SegmentMeanSdDart = int Function(
  ffi.Pointer<ffi.Double> traces,
  int traceCount,
  int sampleCount,
  ffi.Pointer<ffi.Double> meanOut,
  ffi.Pointer<ffi.Double> sdOut,
);

typedef _CallocNative = ffi.Pointer<ffi.Void> Function(
  ffi.IntPtr itemCount,
  ffi.IntPtr itemSize,
);
typedef _CallocDart = ffi.Pointer<ffi.Void> Function(
  int itemCount,
  int itemSize,
);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void> pointer);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void> pointer);

final _BrainstoryEngineLibrary _engineLibrary = _BrainstoryEngineLibrary();
final _NativeMemory _nativeMemory = _NativeMemory();

AggregateSeriesStats? computeAggregateSeriesStats(List<List<double>> traces) {
  if (traces.isEmpty) {
    return null;
  }
  final int sampleCount = traces.first.length;
  if (sampleCount == 0 || traces.any((List<double> trace) => trace.length != sampleCount)) {
    return null;
  }

  final _SegmentMeanSdDart? segmentMeanSd = _engineLibrary.segmentMeanSd;
  if (segmentMeanSd == null || _nativeMemory.unavailable) {
    return null;
  }

  final int traceCount = traces.length;
  final ffi.Pointer<ffi.Double> tracePtr =
      _nativeMemory.callocDouble(traceCount * sampleCount);
  final ffi.Pointer<ffi.Double> meanPtr = _nativeMemory.callocDouble(sampleCount);
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

  _SegmentMeanSdDart? get segmentMeanSd {
    final ffi.DynamicLibrary? library = _library;
    if (library == null) {
      return null;
    }
    return library.lookupFunction<_SegmentMeanSdNative, _SegmentMeanSdDart>(
      'brainstory_segment_mean_sd',
    );
  }

  static ffi.DynamicLibrary? _tryLoadLibrary() {
    if (!Platform.isWindows) {
      return null;
    }

    final Set<String> candidates = <String>{
      'brainstory_engine.dll',
      _join(File(Platform.resolvedExecutable).parent.path, 'brainstory_engine.dll'),
      _join(Directory.current.path, 'brainstory_engine.dll'),
      _join(Directory.current.path, '..\\engine\\target\\debug\\brainstory_engine.dll'),
      _join(Directory.current.path, '..\\engine\\target\\release\\brainstory_engine.dll'),
      _join(Directory.current.path, 'engine\\target\\debug\\brainstory_engine.dll'),
      _join(Directory.current.path, 'engine\\target\\release\\brainstory_engine.dll'),
    };

    for (final String candidate in candidates) {
      try {
        if (candidate == 'brainstory_engine.dll' || File(candidate).existsSync()) {
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
    final String normalizedBase =
        base.endsWith('\\') || base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$normalizedBase\\$leaf';
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

  void free(ffi.Pointer<ffi.Void> pointer) {
    _free(pointer);
  }

  _CallocDart get _calloc => _library!.lookupFunction<_CallocNative, _CallocDart>('calloc');

  _FreeDart get _free => _library!.lookupFunction<_FreeNative, _FreeDart>('free');

  static ffi.DynamicLibrary? _tryLoadLibrary() {
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
