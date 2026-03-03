import 'package:flutter/material.dart';
import 'canvas_logic.dart';

class DatasetPanel extends StatelessWidget {
  final CanvasLogic logic;

  const DatasetPanel({
    super.key,
    required this.logic,
  });

  @override
  Widget build(BuildContext context) {
    // filenames only, sorted alphabetically
    final datasets = logic.datasets.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return Container(
      width: 260,
      color: Colors.grey[850],
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datasets',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          ElevatedButton.icon(
            onPressed: () => logic.pickFiles(),
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
                  child: Text(
                    ds.label,
                    style: const TextStyle(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
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
