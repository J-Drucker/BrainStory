class Dataset {
  final String id;
  String label;
  String path;

  bool loaded = false;

  /// In-memory artifacts (temporary, per-dataset)
  /// Keys like: 'signal.samples', 'signal.fs', 'psd.freqs', 'psd.power'
  final Map<String, dynamic> ram = {};

  Dataset(
      this.id, {
        this.label = '',
        this.path = '',
      });
}
