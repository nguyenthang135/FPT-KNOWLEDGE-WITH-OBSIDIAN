import 'package:flutter/material.dart';
import 'note_file.dart';

class VaultTree extends StatelessWidget {
  const VaultTree({super.key, required this.snapshot, required this.selectedPath,
    required this.onSelect, required this.onRefresh, this.query = ''});
  final VaultSnapshot snapshot;
  final String? selectedPath;
  final ValueChanged<NoteFile> onSelect;
  final VoidCallback? onRefresh;
  final String query;

  bool _matches(VaultNode node) => node.isDirectory
      ? node.children.any(_matches)
      : node.note!.title.toLowerCase().contains(query.trim().toLowerCase());

  Widget _node(VaultNode node) {
    if (!node.isDirectory) {
      return ListTile(
        key: ValueKey(node.path), dense: true,
        leading: const Icon(Icons.description_outlined, size: 18),
        title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(node.note!.relativePath, maxLines: 1,
          overflow: TextOverflow.ellipsis),
        selected: selectedPath == node.path,
        selectedTileColor: const Color(0xFF1E293B),
        onTap: () => onSelect(node.note!),
      );
    }
    return ExpansionTile(
      key: PageStorageKey('${snapshot.root.path}:${node.path}:$query'),
      initiallyExpanded: query.trim().isNotEmpty,
      leading: const Icon(Icons.folder_outlined, size: 18),
      title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      childrenPadding: const EdgeInsets.only(left: 10),
      children: [for (final child in node.children)
        if (query.trim().isEmpty || _matches(child)) _node(child)],
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      ListTile(title: const Text('VAULT'),
        subtitle: Text(snapshot.root.path, maxLines: 2,
          overflow: TextOverflow.ellipsis),
        trailing: IconButton(tooltip: 'Quét lại Vault',
          onPressed: onRefresh, icon: const Icon(Icons.refresh))),
      Text('${snapshot.notes.length} ghi chú Markdown'),
      if (snapshot.notes.isEmpty)
        const Padding(padding: EdgeInsets.all(16),
          child: Text('Vault chưa có file .md.')),
      if (query.trim().isNotEmpty && !snapshot.root.children.any(_matches))
        const Padding(padding: EdgeInsets.all(16),
          child: Text('Không tìm thấy ghi chú phù hợp.')),
      for (final node in snapshot.root.children)
        if (query.trim().isEmpty || _matches(node)) _node(node),
      if (snapshot.warnings.isNotEmpty)
        ExpansionTile(title: Text('${snapshot.warnings.length} cảnh báo'),
          children: [for (final warning in snapshot.warnings)
            ListTile(title: Text(warning))]),
    ],
  );
}
