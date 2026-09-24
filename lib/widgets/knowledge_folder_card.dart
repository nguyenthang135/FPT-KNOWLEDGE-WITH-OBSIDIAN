import 'package:flutter/material.dart';

class KnowledgeFolderCard extends StatelessWidget {
  final bool exporting;
  final String? folderPath;
  final int current;
  final int total;
  final String message;
  final VoidCallback onSync;
  final VoidCallback onChangeFolder;

  const KnowledgeFolderCard({
    super.key,
    required this.exporting,
    required this.folderPath,
    required this.current,
    required this.total,
    required this.message,
    required this.onSync,
    required this.onChangeFolder,
  });

  @override
  Widget build(BuildContext context) {
    final progress = exporting && total > 0 ? current / total : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_copy_outlined, size: 34),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folderPath == null
                            ? 'Knowledge folder'
                            : 'Knowledge folder connected',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (folderPath == null)
                        const Text(
                          'Choose where FPT Knowledge should '
                          'generate your Markdown files.',
                        )
                      else
                        Text(folderPath!),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                if (folderPath != null)
                  TextButton.icon(
                    onPressed: exporting ? null : onChangeFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Change folder'),
                  ),
                if (folderPath != null) const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: exporting ? null : onSync,
                  icon: exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    folderPath == null
                        ? 'Choose folder & sync'
                        : 'Sync with FLM',
                  ),
                ),
              ],
            ),
            if (exporting) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(total > 0 ? '$current / $total — $message' : message),
            ],
          ],
        ),
      ),
    );
  }
}
