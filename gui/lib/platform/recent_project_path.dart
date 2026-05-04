import 'recent_project_path_stub.dart'
    if (dart.library.io) 'recent_project_path_io.dart'
    if (dart.library.js_interop) 'recent_project_path_web.dart' as impl;

Future<String?> readRecentBrainStoryPath() => impl.readRecentBrainStoryPath();

Future<void> writeRecentBrainStoryPath(String? path) =>
    impl.writeRecentBrainStoryPath(path);
