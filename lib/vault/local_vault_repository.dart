import 'dart:convert';
import 'dart:io';
import 'note_file.dart';
import 'vault_repository.dart';

class LocalVaultRepository implements VaultRepository {
  const LocalVaultRepository();

  String _name(String path) => path.replaceAll('\\', '/').split('/')
      .where((part) => part.isNotEmpty).last;

  @override
  Future<VaultSnapshot> scan(String directoryPath) async {
    final root = Directory(directoryPath).absolute;
    final notes = <NoteFile>[];
    final warnings = <String>[];
    Future<VaultNode> visit(Directory directory, String relative,
        {bool isRoot = false}) async {
      final children = <VaultNode>[];
      try {
        // Never follow links/junctions into other vaults or cycles.
        await for (final entity in directory.list(followLinks: false)) {
          final name = _name(entity.path);
          final childRelative = relative.isEmpty ? name : '$relative/$name';
          if (entity is Directory) {
            if (name.toLowerCase() == '.obsidian') continue;
            children.add(await visit(entity, childRelative));
          } else if (entity is File && name.toLowerCase().endsWith('.md')) {
            try {
              final stat = await entity.stat();
              if (stat.type != FileSystemEntityType.file) {
                throw const FileSystemException('File disappeared');
              }
              final note = NoteFile(path: entity.path,
                relativePath: childRelative, name: name,
                modified: stat.modified, sizeBytes: stat.size);
              notes.add(note);
              children.add(VaultNode(name: name, path: entity.path, note: note));
            } on FileSystemException {
              warnings.add('Không lấy được thông tin: $childRelative');
            }
          }
        }
      } on FileSystemException {
        if (isRoot) {
          throw const VaultException(
              'Không mở được Vault. Kiểm tra thư mục và quyền truy cập.');
        }
        warnings.add('Không đọc được thư mục: $relative');
      }
      children.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        final order = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return order == 0 ? a.name.compareTo(b.name) : order;
      });
      return VaultNode(name: isRoot ? directory.path : _name(directory.path),
        path: directory.path, children: List.unmodifiable(children));
    }
    final tree = await visit(root, '', isRoot: true);
    notes.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return VaultSnapshot(root: tree, notes: List.unmodifiable(notes),
      warnings: List.unmodifiable(warnings));
  }

  @override
  Future<NoteFile> readNote(NoteFile note) async {
    try {
      final file = File(note.path);
      final bytes = await file.readAsBytes();
      var content = utf8.decode(bytes, allowMalformed: false);
      if (content.startsWith('\uFEFF')) content = content.substring(1);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw const FileSystemException('File disappeared');
      }
      return NoteFile(path: note.path, relativePath: note.relativePath,
        name: note.name, modified: stat.modified, sizeBytes: bytes.length,
        content: content, tags: note.tags);
    } on FormatException {
      throw const VaultException('File không phải UTF-8 hợp lệ. Hãy lưu lại file bằng UTF-8.');
    } on FileSystemException {
      throw const VaultException('Không đọc được file: file đã bị xóa, di chuyển hoặc không có quyền truy cập.');
    }
  }
}
