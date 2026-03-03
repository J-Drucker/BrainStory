import 'package:flutter/material.dart';
import 'canvas_logic.dart';
import '../nodes/node_registry.dart';
import 'dataset_panel.dart';

class CanvasView extends StatelessWidget {
  final CanvasLogic logic;

  const CanvasView({
    super.key,
    required this.logic,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ---- LEFT: Sidebar (grouped nodes) ----
        Container(
          width: 240,
          color: Colors.grey[900],
          padding: const EdgeInsets.all(10),
          child: ListView(
            children: [
              const Text(
                'Nodes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              for (final group in NodeRegistry.groupOrder) ...[
                _GroupHeader(title: group.label),
                const SizedBox(height: 6),

                for (final entry in logic.entriesForGroup(group))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ElevatedButton(
                      onPressed: () => logic.addNode(entry.create()),
                      child: Text(entry.create().title),
                    ),
                  ),

                const SizedBox(height: 14),
              ],
            ],
          ),
        ),

        // ---- CENTER: Canvas ----
        Expanded(
          child: GestureDetector(
            onTap: logic.clearSelection,
            child: Stack(
              children: [
                ...logic.connectionWidgets(),
                ...logic.nodeWidgets(
                  context: context,
                  update: () => logic.update(),
                ),
              ],
            ),
          ),
        ),

        // ---- RIGHT: Dataset Panel ----
        DatasetPanel(logic: logic),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}