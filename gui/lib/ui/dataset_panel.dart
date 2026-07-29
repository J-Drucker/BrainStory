import 'package:flutter/material.dart';
import '../nodes/import_node.dart';
import 'canvas_logic.dart';

class DatasetPanel extends StatelessWidget {
  final CanvasLogic logic;
  final VoidCallback onChanged;

  const DatasetPanel({super.key, required this.logic, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // filenames only, sorted alphabetically
    final datasets = logic.datasets.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datasets',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          ElevatedButton.icon(
            onPressed: () async {
              try {
                await logic.pickFiles();
                onChanged();
              } catch (error, stackTrace) {
                debugPrint('BrainStory: Add files failed: $error');
                debugPrintStack(stackTrace: stackTrace);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not open file picker: $error'),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add files'),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: datasets.isEmpty
                ? const Center(
                    child: Text(
                      'No files added',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: datasets.length,
                    itemBuilder: (context, index) {
                      final ds = datasets[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    ds.label,
                                    style: const TextStyle(color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (datasetSourceName(ds) != ds.label)
                                    Text(
                                      datasetSourceName(ds),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove dataset',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white54,
                                size: 18,
                              ),
                              onPressed: () async {
                                if (logic.isDatasetMutationLocked(ds.id)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${ds.label} is being used by the active job.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final bool? confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (BuildContext dialogContext) {
                                    return AlertDialog(
                                      title: const Text('Remove dataset?'),
                                      content: Text(
                                        'Remove ${ds.label} from this BrainStory project? Cached outputs tied to it will also be removed.',
                                      ),
                                      actions: <Widget>[
                                        TextButton(
                                          onPressed: () => Navigator.of(
                                            dialogContext,
                                          ).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.of(
                                            dialogContext,
                                          ).pop(true),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                                if (confirmed != true) {
                                  return;
                                }
                                await logic.removeDataset(ds.id);
                                onChanged();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
