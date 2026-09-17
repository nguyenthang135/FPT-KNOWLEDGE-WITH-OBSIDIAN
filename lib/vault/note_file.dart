/// Shared contract for the viewer, search and vault modules.
/// During scanning content is null; an empty string means a loaded empty file.
class NoteFile {
  const NoteFile({required this.path, required this.relativePath,
    required this.name, required this.modified, required this.sizeBytes,
    this.content, this.tags = const []});
  final String path;
  final String relativePath;
  final String name;
  final DateTime modified;
  final int sizeBytes;
  final String? content;
  final List<String> tags;
  String get title => name.substring(0, name.length - 3);
  String get course => relativePath.contains('/')
      ? relativePath.split('/').first : 'Vault';
}

class VaultNode {
  const VaultNode({required this.name, required this.path,
    this.note, this.children = const []});
  final String name;
  final String path;
  final NoteFile? note;
  final List<VaultNode> children;
  bool get isDirectory => note == null;
}

class VaultSnapshot {
  const VaultSnapshot({required this.root, required this.notes,
    this.warnings = const []});
  final VaultNode root;
  final List<NoteFile> notes;
  final List<String> warnings;
}

class VaultException implements Exception {
  const VaultException(this.message);
  final String message;
  @override
  String toString() => message;
}
