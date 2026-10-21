import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

// Serialize the two supported writers; readers remain available while staging.
Future<void> _databaseWriter = Future<void>.value();
Future<T> withDatabaseWriteLock<T>(Future<T> Function() action) {
  final result = _databaseWriter.then((_) => action());
  _databaseWriter = result.then<void>((_) {}, onError: (Object _) {});
  return result;
}

bool isManagedDatabasePath(String name) =>
    const {
      'database_index.json',
      'release_metadata.json',
      'search_index.json',
      'managed_manifest.json',
      'flm_sync_state.json',
    }.contains(name) ||
    RegExp(
      r'^(curricula|subjects|specializations)/[A-Za-z0-9_(). -]+\.json$',
    ).hasMatch(name);

String databaseHash(List<int> bytes) => sha256.convert(bytes).toString();

Future<void> verifyManagedDatabase(Directory root) async {
  final manifestFile = File('${root.path}/managed_manifest.json');
  if (!await manifestFile.exists()) return; // Legacy maintainer database.
  final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
  final files = manifest['files'] as Map;
  if (files.isEmpty || files.length > 20000) {
    throw const FormatException('Invalid managed manifest');
  }
  for (final entry in files.entries) {
    final path = entry.key.toString();
    if (!isManagedDatabasePath(path) || path == 'managed_manifest.json') {
      throw const FormatException('Unsafe managed path');
    }
    final record = entry.value as Map;
    final file = File('${root.path}/$path');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FormatException('Missing managed file: $path');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != record['size'] ||
        databaseHash(bytes) != record['sha256']) {
      throw FormatException('Managed file integrity failed: $path');
    }
  }
}
