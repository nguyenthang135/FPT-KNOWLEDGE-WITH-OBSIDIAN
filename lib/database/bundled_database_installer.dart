import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

typedef DatabaseAssetLoader = Future<Uint8List> Function();

class DatabaseValidation {
  final bool valid;
  final String? error;
  final Map<String, dynamic>? index;
  final Map<String, dynamic>? metadata;

  const DatabaseValidation({
    required this.valid,
    this.error,
    this.index,
    this.metadata,
  });
}

class BundledDatabaseInstaller {
  static const assetPath = 'assets/database/fpt_knowledge_database.zip';
  static const supportedSchemaVersion = 1;

  final Directory databaseDirectory;
  final DatabaseAssetLoader _assetLoader;

  BundledDatabaseInstaller({
    Directory? databaseDirectory,
    DatabaseAssetLoader? assetLoader,
  }) : databaseDirectory =
           databaseDirectory ??
           Directory(
             '${Platform.environment['APPDATA'] ?? Directory.current.path}'
             '${Platform.pathSeparator}FPT Knowledge'
             '${Platform.pathSeparator}Database',
           ),
       _assetLoader =
           assetLoader ??
           (() async {
             final data = await rootBundle.load(assetPath);
             return data.buffer.asUint8List(
               data.offsetInBytes,
               data.lengthInBytes,
             );
           });

  Future<Directory> ensureInstalled() async {
    final bundleBytes = await _assetLoader();
    final bundledMetadata = _readBundledMetadata(bundleBytes);
    final local = await validate(databaseDirectory);

    if (local.valid &&
        !_bundleIsNewer(bundledMetadata, local.metadata, local.index)) {
      return databaseDirectory;
    }

    await _installSafely(bundleBytes);
    final installed = await validate(databaseDirectory);
    if (!installed.valid) {
      throw StateError(
        'Bundled database installation failed validation: '
        '${installed.error ?? 'unknown error'}',
      );
    }
    return databaseDirectory;
  }

  Future<DatabaseValidation> validate(Directory root) async {
    try {
      final indexFile = File(
        '${root.path}${Platform.pathSeparator}database_index.json',
      );
      final curricula = Directory(
        '${root.path}${Platform.pathSeparator}curricula',
      );
      final subjects = Directory(
        '${root.path}${Platform.pathSeparator}subjects',
      );
      if (!await indexFile.exists() ||
          !await curricula.exists() ||
          !await subjects.exists()) {
        return const DatabaseValidation(
          valid: false,
          error: 'Required database files are missing.',
        );
      }

      final index = _decodeObject(await indexFile.readAsString());
      final curriculumCount =
          int.tryParse(index['curriculumCount']?.toString() ?? '') ?? 0;
      final subjectCount =
          int.tryParse(index['subjectCount']?.toString() ?? '') ?? 0;
      if (curriculumCount <= 0 || subjectCount <= 0) {
        return const DatabaseValidation(
          valid: false,
          error: 'Database index contains empty counts.',
        );
      }

      final curriculumFiles = await _readableJsonCount(curricula);
      final subjectFiles = await _readableJsonCount(subjects);
      if (curriculumFiles < curriculumCount || subjectFiles < subjectCount) {
        return DatabaseValidation(
          valid: false,
          error:
              'Database records are missing or unreadable '
              '($curriculumFiles/$curriculumCount curricula, '
              '$subjectFiles/$subjectCount subjects).',
        );
      }

      Map<String, dynamic>? metadata;
      final metadataFile = File(
        '${root.path}${Platform.pathSeparator}release_metadata.json',
      );
      if (await metadataFile.exists()) {
        metadata = _decodeObject(await metadataFile.readAsString());
        final schema =
            int.tryParse(metadata['schemaVersion']?.toString() ?? '') ?? 0;
        if (schema != supportedSchemaVersion) {
          return DatabaseValidation(
            valid: false,
            error: 'Unsupported database schema version: $schema.',
          );
        }
      }

      return DatabaseValidation(valid: true, index: index, metadata: metadata);
    } catch (error) {
      return DatabaseValidation(valid: false, error: error.toString());
    }
  }

  Map<String, dynamic> _readBundledMetadata(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.files.firstWhere(
      (entry) => entry.name == 'Database/release_metadata.json',
      orElse: () => throw StateError(
        'Bundled database release_metadata.json is missing.',
      ),
    );
    final metadata = _decodeObject(utf8.decode(file.content as List<int>));
    final schema =
        int.tryParse(metadata['schemaVersion']?.toString() ?? '') ?? 0;
    if (schema != supportedSchemaVersion) {
      throw StateError('Unsupported bundled schema version: $schema.');
    }
    return metadata;
  }

  bool _bundleIsNewer(
    Map<String, dynamic> bundled,
    Map<String, dynamic>? localMetadata,
    Map<String, dynamic>? localIndex,
  ) {
    if (localMetadata == null) {
      final bundledCurricula =
          int.tryParse(bundled['curriculumCount']?.toString() ?? '') ?? 0;
      final bundledSubjects =
          int.tryParse(bundled['subjectCount']?.toString() ?? '') ?? 0;
      final localCurricula =
          int.tryParse(localIndex?['curriculumCount']?.toString() ?? '') ?? 0;
      final localSubjects =
          int.tryParse(localIndex?['subjectCount']?.toString() ?? '') ?? 0;
      return localCurricula < bundledCurricula ||
          localSubjects < bundledSubjects;
    }

    final bundledDatabase =
        int.tryParse(bundled['databaseVersion']?.toString() ?? '') ?? 0;
    final localDatabase =
        int.tryParse(localMetadata['databaseVersion']?.toString() ?? '') ?? 0;
    if (bundledDatabase != localDatabase) {
      return bundledDatabase > localDatabase;
    }
    final bundledSchema =
        int.tryParse(bundled['schemaVersion']?.toString() ?? '') ?? 0;
    final localSchema =
        int.tryParse(localMetadata['schemaVersion']?.toString() ?? '') ?? 0;
    if (bundledSchema != localSchema) {
      return bundledSchema > localSchema;
    }
    final bundledAt = DateTime.tryParse(bundled['builtAt']?.toString() ?? '');
    final localAt = DateTime.tryParse(
      localMetadata['builtAt']?.toString() ?? '',
    );
    return bundledAt != null && (localAt == null || bundledAt.isAfter(localAt));
  }

  Future<void> _installSafely(Uint8List bytes) async {
    final parent = databaseDirectory.parent;
    await parent.create(recursive: true);
    final temporary = Directory(
      '${parent.path}${Platform.pathSeparator}Database.installing',
    );
    final backup = Directory(
      '${parent.path}${Platform.pathSeparator}Database.backup',
    );
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
    await temporary.create(recursive: true);

    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive.files.where((item) => item.isFile)) {
        const prefix = 'Database/';
        if (!entry.name.startsWith(prefix)) continue;
        final relative = entry.name.substring(prefix.length);
        if (relative.isEmpty ||
            relative.contains('..') ||
            relative.startsWith('/') ||
            relative.startsWith('\\')) {
          throw StateError('Unsafe database ZIP entry: ${entry.name}');
        }
        final target = File(
          '${temporary.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        );
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.content as List<int>, flush: true);
      }

      final staged = await validate(temporary);
      if (!staged.valid) {
        throw StateError('Bundled database is invalid: ${staged.error}');
      }

      if (await backup.exists()) {
        await backup.delete(recursive: true);
      }
      final hadLocal = await databaseDirectory.exists();
      if (hadLocal) {
        await databaseDirectory.rename(backup.path);
      }
      try {
        await temporary.rename(databaseDirectory.path);
      } catch (_) {
        if (hadLocal &&
            !await databaseDirectory.exists() &&
            await backup.exists()) {
          await backup.rename(databaseDirectory.path);
        }
        rethrow;
      }
      if (await backup.exists()) {
        await backup.delete(recursive: true);
      }
    } finally {
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  Future<int> _readableJsonCount(Directory directory) async {
    var count = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      _decodeObject(await entity.readAsString());
      count++;
    }
    return count;
  }

  Map<String, dynamic> _decodeObject(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
