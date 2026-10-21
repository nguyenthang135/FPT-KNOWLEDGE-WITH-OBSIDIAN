import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:fptu_se_brain/database/database_integrity.dart';

Map<String, List<int>> readSnapshot(String path) {
  final result = <String, List<int>>{};
  final archive = ZipDecoder().decodeBytes(
    File(path).readAsBytesSync(),
    verify: true,
  );
  for (final entry in archive.files.where((entry) => entry.isFile)) {
    if (!entry.name.startsWith('Database/')) {
      throw const FormatException('Unexpected ZIP root');
    }
    final name = entry.name.substring(9);
    if (!isManagedDatabasePath(name) ||
        result.containsKey(name) ||
        entry.isSymbolicLink) {
      throw FormatException('Unsafe/duplicate ZIP entry: $name');
    }
    result[name] = entry.content;
  }
  return result;
}

Map<String, dynamic> object(List<int> bytes) =>
    Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
List<int> encode(Object value) => utf8.encode(jsonEncode(value));
String recordName(String code) => code
    .trim()
    .toUpperCase()
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), '_');

Map<String, dynamic> manifest(Map<String, List<int>> files) => {
  'schemaVersion': 1,
  'files': {
    for (final name in files.keys.toList()..sort())
      if (name != 'managed_manifest.json')
        name: {
          'size': files[name]!.length,
          'sha256': databaseHash(files[name]!),
        },
  },
};

void writeZip(String path, Map<String, List<int>> files, {String prefix = ''}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile('$prefix${entry.key}', entry.value.length, entry.value),
    );
  }
  File(path).parent.createSync(recursive: true);
  File(path).writeAsBytesSync(ZipEncoder().encode(archive));
}

void main(List<String> args) {
  if (args.length == 2 && args[0] == 'prepare') {
    final files = readSnapshot(args[1]);
    final metadata = object(files['release_metadata.json']!);
    final index = object(files['database_index.json']!);
    final curricula = files.keys
        .where((path) => path.startsWith('curricula/'))
        .toList();
    final subjects = files.keys
        .where((path) => path.startsWith('subjects/'))
        .toList();
    if (metadata['schemaVersion'] != 1 ||
        curricula.length != index['curriculumCount'] ||
        subjects.length != index['subjectCount']) {
      throw const FormatException('Snapshot counts/schema do not match');
    }
    final records = <Map<String, String>>[];
    final missing = <String>{};
    var syllabusDetails = 0;
    for (final path in curricula) {
      final data = object(files[path]!);
      final code = data['code'].toString();
      if (path != 'curricula/$code.json' ||
          !(index['curricula'] as List).contains(code)) {
        throw FormatException('Curriculum index mismatch: $path');
      }
      final specializations = files['specializations/$code.json'];
      final choices = specializations == null
          ? []
          : object(specializations)['specializations'] as List? ?? [];
      final names = choices
          .whereType<Map>()
          .map((item) => item['name'])
          .join(' ');
      records.add({
        'type': 'curriculum',
        'code': code,
        'name': data['name']?.toString() ?? code,
        'searchableText': '$code ${data['name']} $names',
      });
      for (final semester
          in (data['semesters'] as List? ?? []).whereType<Map>()) {
        for (final subject
            in (semester['subjects'] as List? ?? []).whereType<Map>()) {
          final reference = subject['code'].toString();
          if (subject['isComboPlaceholder'] != true &&
              !files.containsKey('subjects/${recordName(reference)}.json')) {
            missing.add(reference);
          }
        }
      }
    }
    for (final path in subjects) {
      final data = object(files[path]!);
      final code = data['code'].toString();
      if (path != 'subjects/${recordName(code)}.json') {
        throw FormatException('Subject code mismatch: $path');
      }
      final syllabus = data['syllabusName']?.toString() ?? '';
      final english = data['englishName']?.toString() ?? '';
      if ((data['learningOutcomes'] as List? ?? []).isNotEmpty) {
        syllabusDetails++;
      }
      records.add({
        'type': 'subject',
        'code': code,
        'name': syllabus.isNotEmpty ? syllabus : english,
        'searchableText': '$code $syllabus $english',
      });
    }
    if (missing.isNotEmpty) {
      throw FormatException(
        'Unresolved subject references (${missing.length}): ${missing.take(12).join(', ')}',
      );
    }
    for (final code in ['CEA201', 'PRM393']) {
      if (!files.containsKey('subjects/$code.json')) {
        throw FormatException('Required subject missing: $code');
      }
    }
    files['search_index.json'] = encode({'records': records});
    files['managed_manifest.json'] = encode(manifest(files));
    writeZip(args[1], files, prefix: 'Database/');
    final bytes = File(args[1]).readAsBytesSync();
    final descriptor = {
      ...metadata,
      'databaseSha256': databaseHash(bytes),
      'archiveBytes': bytes.length,
      'managedFiles': files.length,
      'managedManifestSha256': databaseHash(files['managed_manifest.json']!),
      'subjectsWithOutcomes': syllabusDetails,
    };
    File(
      '${File(args[1]).parent.path}/bundle_info.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(descriptor));
    stdout.writeln(jsonEncode(descriptor));
  } else if (args.length == 4 && args[0] == 'delta') {
    final old = readSnapshot(args[1]);
    final next = readSnapshot(args[2]);
    final baseVersion = object(
      old['release_metadata.json']!,
    )['databaseVersion'];
    final nextVersion = object(
      next['release_metadata.json']!,
    )['databaseVersion'];
    if (baseVersion is! int ||
        nextVersion is! int ||
        nextVersion <= baseVersion) {
      throw const FormatException('Dataset version must increase');
    }
    final changed = <String, List<int>>{};
    final removed = old.keys.where((path) => !next.containsKey(path)).toList();
    for (final entry in next.entries) {
      if (old[entry.key] == null ||
          databaseHash(old[entry.key]!) != databaseHash(entry.value)) {
        changed[entry.key] = entry.value;
      }
    }
    writeZip(args[3], changed);
    final bytes = File(args[3]).readAsBytesSync();
    File('${args[3]}.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'baseVersion': baseVersion,
        'databaseVersion': nextVersion,
        'minAppVersion': '1.0.1', 'maxAppMajor': 1,
        'delta': {
          'size': bytes.length,
          'sha256': databaseHash(bytes),
          'url': File(args[3]).uri.pathSegments.last,
        },
        'changed': manifest(changed)['files'],
        // The managed manifest itself is safe to transfer, and needs its own hash.
        if (changed.containsKey('managed_manifest.json'))
          'managedManifest': {
            'size': changed['managed_manifest.json']!.length,
            'sha256': databaseHash(changed['managed_manifest.json']!),
          },
        'removed': removed,
      }),
    );
    stdout.writeln(
      'Delta: ${changed.length} changed, ${removed.length} removed; ${bytes.length} bytes',
    );
  } else {
    stderr.writeln(
      'Usage: dart run tool/release_database.dart prepare <snapshot.zip> | delta <old.zip> <new.zip> <delta.zip>',
    );
    exitCode = 64;
  }
}
