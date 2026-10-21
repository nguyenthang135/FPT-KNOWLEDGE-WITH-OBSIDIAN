import 'dart:convert';
import 'dart:io';

import '../flm/flm_session.dart';
import '../flm/flm_syllabus_service.dart';
import 'bundled_database_installer.dart';
import 'database_integrity.dart';
import 'database_repository.dart';
import 'flm_database_collector.dart';
import 'flm_database_models.dart';
import 'json_store.dart';

class FlmUpdateResult {
  final int added,
      modified,
      skipped,
      detailDownloads,
      inventoryPages,
      inventoryBytes;
  final Duration elapsed;
  final bool deep;
  final List<String> unavailableSubjects;
  const FlmUpdateResult(
    this.added,
    this.modified,
    this.skipped,
    this.detailDownloads,
    this.inventoryPages,
    this.inventoryBytes,
    this.elapsed,
    this.deep, {
    this.unavailableSubjects = const [],
  });

  String get message =>
      '${added + modified == 0 ? 'No differences found' : 'Updated: $added new, $modified modified'}.'
      '\n${deep ? 'Visible curriculum details checked against FLM.' : 'New curriculum IDs checked. Existing content changes cannot be detected from IDs alone.'}'
      '\nOnly records visible to your FLM account were checked; nothing was deleted.'
      '${unavailableSubjects.isEmpty ? '' : '\nFLM returned no visible syllabus for: ${unavailableSubjects.join(', ')}. Curriculum rows are retained; missing syllabus content was not invented. Quick checks retry availability after 24 hours; deeper checking retries now.'}';
}

class FlmAuthenticationExpired implements Exception {}

// FLM's existing list parser exposes codes, not authoritative revision markers.
// Quick mode is deliberately additions-only. Deeper checking is opt-in, never
// silently substituted for a cheap inventory check.
class FlmIncrementalUpdater {
  final DatabaseRepository repository;
  final CurriculumDiscoverer? discover;
  final CurriculumExtractor? extractCurriculum;
  final SyllabusExtractor? extractSyllabus;
  final FlmSession session;
  bool _busy = false;

  FlmIncrementalUpdater(
    this.repository, {
    this.discover,
    this.extractCurriculum,
    this.extractSyllabus,
    FlmSession? session,
  }) : session = session ?? FlmSession.instance;

  Future<FlmUpdateResult> check({
    bool verifyExisting = false,
    void Function(String)? onProgress,
  }) async {
    if (_busy) throw StateError('An FLM check is already running.');
    _busy = true;
    try {
      return await withDatabaseWriteLock(
        () => _check(verifyExisting, onProgress),
      );
    } finally {
      _busy = false;
    }
  }

  Future<FlmUpdateResult> _check(
    bool deep,
    void Function(String)? progress,
  ) async {
    final clock = Stopwatch()..start();
    final root = repository.root;
    final pending = JsonStore(root: Directory('${root.path}.flm-pending'));
    final stage = Directory('${root.path}.flm-staging');
    final backup = Directory('${root.path}.backup');
    var pages = 0,
        bytes = 0,
        downloads = 0,
        added = 0,
        modified = 0,
        skipped = 0;
    final headers = <String>{};
    String? downloadingCode;
    progress?.call('Checking FLM…');
    final codes =
        (await (discover?.call() ??
                session.discoverCurriculumCodes(
                  verifyKnownTarget: false,
                  onDiagnostics: (value) {
                    if (value.rowsFound > 0) {
                      pages++;
                      bytes += value.approximateBytes;
                      headers.addAll(value.headers);
                    }
                  },
                )))
            .toSet()
            .toList()
          ..sort();
    if (codes.isEmpty || codes.any((code) => !_validCode(code))) {
      throw const FormatException('Incomplete FLM inventory.');
    }
    await JsonStore(root: root).writeLog('flm-inventory-check.json', {
      'codes': codes.length,
      'inventoryPages': pages,
      'approximateInventoryHtmlBytes': bytes,
      'inventoryHeaders': headers.toList(),
      'elapsedMs': clock.elapsedMilliseconds,
      'scope': 'visible-curriculum-ids-only',
    });
    await repository.initialize();
    final local = JsonStore(root: root);
    final availability =
        await local.readLog('flm-unavailable-syllabi.json') ?? {};
    final unavailable = <String, dynamic>{};
    final targets = <String>[];
    for (final code in codes) {
      if (deep || !await repository.containsCurriculum(code)) {
        targets.add(code);
      } else {
        skipped++;
      }
    }
    final plan = {'codes': targets, 'deep': deep};
    final savedPlan = await pending.readRoot('plan.json');
    final created = DateTime.tryParse(
      savedPlan?['createdAt']?.toString() ?? '',
    );
    final reuseCheckpoint =
        savedPlan?['completed'] != true &&
        created != null &&
        DateTime.now().difference(created) <= const Duration(hours: 24);
    if (!reuseCheckpoint) {
      if (await pending.root.exists()) {
        final history = Directory('${root.path}.flm-history');
        await history.create(recursive: true);
        await pending.root.rename(
          '${history.path}/${DateTime.now().microsecondsSinceEpoch}',
        );
      }
    }
    await pending.writeRoot('plan.json', {
      'signature': jsonEncode(plan),
      'createdAt': reuseCheckpoint
          ? created.toUtc().toIso8601String()
          : DateTime.now().toUtc().toIso8601String(),
      'completed': false,
    });
    final collector = FlmDatabaseCollector(session: session, store: pending);
    final updates = <String, Map<String, dynamic>>{};
    final subjects = <String>{};
    subjects.addAll(availability.keys.where(_validCode));
    Future<void> put(String path, Map<String, dynamic> value) async {
      final old = await local.readJson('${root.path}/$path');
      if (old != null) {
        // A restricted or truncated detail page must not erase installed rows.
        int rows(dynamic node) {
          if (node is Map) {
            return node.entries.fold<int>(0, (n, e) => n + rows(e.value));
          }
          if (node is List) {
            return node.length + node.fold<int>(0, (n, e) => n + rows(e));
          }
          return 0;
        }

        if (rows(value) < rows(old)) {
          throw const FormatException(
            'FLM detail appears incomplete; keeping installed records.',
          );
        }
      }
      if (_contentHash(old) == _contentHash(value)) {
        skipped++;
        return;
      }
      if (old == null) {
        added++;
      } else {
        modified++;
      }
      updates[path] = value;
    }

    try {
      for (var i = 0; i < targets.length; i++) {
        final code = targets[i];
        downloadingCode = code;
        progress?.call('Downloading curriculum ${i + 1} of ${targets.length}…');
        var cached = await pending.readLog('$code.complete.json');
        if (cached != null) {
          final digest = cached.remove('checkpointHash');
          if (digest != _contentHash(cached)) cached = null;
        }
        if (cached == null) {
          final data =
              await (extractCurriculum?.call(code) ??
                  collector.fetchCurriculumRecord(code));
          downloads++;
          if (data.code != code || data.subjects.isEmpty) {
            throw const FormatException('Incomplete curriculum.');
          }
          cached = {
            'curriculum': data.curriculumJson(DateTime.now()),
            'specializations': data.specializationsJson(DateTime.now()),
            'subjects': data.uniqueSubjectCodes.toList()..sort(),
          };
          await pending.writeLog('$code.complete.json', {
            ...cached,
            'checkpointHash': _contentHash(cached),
          });
        }
        await put(
          'curricula/$code.json',
          _markOptionSlots(
            Map<String, dynamic>.from(cached['curriculum'] as Map),
          ),
        );
        await put(
          'specializations/$code.json',
          Map<String, dynamic>.from(cached['specializations'] as Map),
        );
        subjects.addAll(
          (cached['subjects'] as List).cast<String>().where(
            (code) => !_isOptionSlot(code),
          ),
        );
      }
      final subjectTargets = <String>[];
      for (final code in subjects.toList()..sort()) {
        if (!_validCode(code)) {
          throw const FormatException('Invalid subject identity.');
        }
        if (deep ||
            await local.readJson(local.recordPath('subjects', code)) == null) {
          subjectTargets.add(code);
        } else {
          skipped++;
        }
      }
      for (var i = 0; i < subjectTargets.length; i++) {
        final code = subjectTargets[i];
        downloadingCode = code;
        final checked = DateTime.tryParse(availability[code]?.toString() ?? '');
        if (!deep &&
            checked != null &&
            !checked.isAfter(DateTime.now()) &&
            DateTime.now().difference(checked) < const Duration(hours: 24)) {
          unavailable[code] = availability[code];
          skipped++;
          continue;
        }
        progress?.call(
          'Downloading subject ${i + 1} of ${subjectTargets.length}…',
        );
        final checkpoint = await pending.readLog('$code.syllabus.json');
        Map<String, dynamic>? value;
        if (checkpoint != null) {
          value = Map<String, dynamic>.from(checkpoint['payload'] as Map);
          if (checkpoint['sha256'] != _contentHash(value)) value = null;
        }
        if (value == null) {
          SyllabusDetailResult data;
          try {
            data =
                await (extractSyllabus?.call(code) ??
                    FlmSyllabusService(
                      session: session,
                    ).loadExactSyllabus(code));
          } on FlmSyllabusUnavailable {
            unavailable[code] = DateTime.now().toUtc().toIso8601String();
            continue;
          }
          downloads++;
          if (data.subjectCode != code ||
              (data.syllabusName.isEmpty && data.courseNameEnglish.isEmpty)) {
            throw const FormatException('Incomplete subject.');
          }
          value = syllabusJson(data, DateTime.now());
          await pending.writeLog('$code.syllabus.json', {
            'payload': value,
            'sha256': _contentHash(value),
          });
        }
        await put('subjects/$code.json', value);
      }
      if (updates.isNotEmpty) {
        progress?.call('Installing verified updates…');
        if (await stage.exists()) await stage.delete(recursive: true);
        await _copyTree(root, stage);
        final staged = JsonStore(root: stage);
        for (final entry in updates.entries) {
          await staged.writeRoot(entry.key, entry.value);
        }
        final curricula = await staged.readRecords('curricula');
        final syllabi = await staged.readRecords('subjects');
        final specializations = await staged.readRecords('specializations');
        final index = {
          ...repository.index,
          'curriculumCount': curricula.length,
          'subjectCount': syllabi.length,
          'syllabusCount': syllabi.length,
          'specializationCurriculumCount': specializations
              .where((r) => (r['specializations'] as List).isNotEmpty)
              .length,
          'curricula': curricula.map((r) => r['code'] as String).toList()
            ..sort(),
          'subjects': syllabi.map((r) => r['code'] as String).toList()..sort(),
          'lastUpdatedAt': DateTime.now().toUtc().toIso8601String(),
        };
        await staged.writeRoot('database_index.json', index);
        final metadata = await local.readRoot('release_metadata.json');
        await staged.writeRoot('release_metadata.json', {
          ...?metadata,
          'schemaVersion': 1,
          'databaseVersion': (metadata?['databaseVersion'] as int? ?? 1) + 1,
          'builtAt': DateTime.now().toUtc().toIso8601String(),
          'curriculumCount': curricula.length,
          'subjectCount': syllabi.length,
          'syllabusCount': syllabi.length,
          'source': 'Authenticated local FLM update',
        });
        final previous = await local.readRoot('flm_sync_state.json');
        await staged.writeRoot('flm_sync_state.json', {
          'scope': deep ? 'visible-details' : 'new-curriculum-ids',
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'hashes': {
            ...?(previous?['hashes'] as Map?),
            for (final entry in updates.entries)
              entry.key: _contentHash(entry.value),
          },
        });
        await DatabaseRepository(stage).rebuildSearchIndex();
        final hashes = <String, dynamic>{};
        await for (final file in stage.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is! File) continue;
          final path = file.path
              .substring(stage.path.length + 1)
              .replaceAll('\\', '/');
          if (!isManagedDatabasePath(path) || path == 'managed_manifest.json') {
            continue;
          }
          final content = await file.readAsBytes();
          hashes[path] = {
            'size': content.length,
            'sha256': databaseHash(content),
          };
        }
        await staged.writeRoot('managed_manifest.json', {'files': hashes});
        final validation = await BundledDatabaseInstaller(
          databaseDirectory: root,
        ).validate(stage);
        if (!validation.valid) {
          throw const FormatException('Updated database failed validation.');
        }
        await BundledDatabaseInstaller.writeInstallationMarker(stage, null);
        if (await backup.exists()) await backup.delete(recursive: true);
        await root.rename(backup.path);
        try {
          await stage.rename(root.path);
        } catch (_) {
          await backup.rename(root.path);
          rethrow;
        }
        // Retain one complete recovery copy until the next successful install.
        await repository.initialize();
      }
      await pending.writeRoot('plan.json', {
        'signature': jsonEncode(plan),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'completed': true,
      });
      final result = FlmUpdateResult(
        added,
        modified,
        skipped,
        downloads,
        pages,
        bytes,
        clock.elapsed,
        deep,
        unavailableSubjects: unavailable.keys.toList()..sort(),
      );
      await JsonStore(
        root: root,
      ).writeLog('flm-unavailable-syllabi.json', unavailable);
      await JsonStore(root: root).writeLog('flm-last-check.json', {
        'added': added,
        'modified': modified,
        'skipped': skipped,
        'detailDownloads': downloads,
        'inventoryPages': pages,
        'approximateInventoryHtmlBytes': bytes,
        'elapsedMs': clock.elapsedMilliseconds,
        'scope': deep ? 'visible-details' : 'new-curriculum-ids',
        'inventoryHeaders': headers.toList(),
        'unavailableSubjects': unavailable.keys.toList()..sort(),
      });
      return result;
    } catch (error) {
      await JsonStore(root: root).writeLog('flm-last-failure.json', {
        'record': downloadingCode,
        'errorType': error.runtimeType.toString(),
        'detailDownloads': downloads,
        'loginRequired': discover == null
            ? await session.loginRequired()
            : false,
      });
      if (discover == null) {
        if (!session.isAuthenticated || await session.loginRequired()) {
          throw FlmAuthenticationExpired();
        }
      }
      rethrow;
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  static bool _validCode(String value) =>
      RegExp(r'^[A-Z0-9_(). -]{2,150}$').hasMatch(value);
  static bool _isOptionSlot(String code) =>
      RegExp(r'^[A-Z0-9_]+\*\d+$').hasMatch(code);
  static Map<String, dynamic> _markOptionSlots(
    Map<String, dynamic> curriculum,
  ) {
    for (final semester in curriculum['semesters'] as List) {
      for (final subject in (semester as Map)['subjects'] as List) {
        if (_isOptionSlot((subject as Map)['code'].toString())) {
          subject['isComboPlaceholder'] = true;
        }
      }
    }
    return curriculum;
  }

  static String? _contentHash(Map<String, dynamic>? value) {
    if (value == null) return null;
    dynamic stable(dynamic node) {
      if (node is Map) {
        final keys =
            node.keys.cast<String>().where((k) => k != 'fetchedAt').toList()
              ..sort();
        return {for (final key in keys) key: stable(node[key])};
      }
      if (node is List) return node.map(stable).toList();
      return node;
    }

    return databaseHash(utf8.encode(jsonEncode(stable(value))));
  }

  static Future<void> _copyTree(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entity is File) {
        await entity.copy('${target.path}/$name');
      } else if (entity is Directory) {
        await _copyTree(entity, Directory('${target.path}/$name'));
      } else {
        throw const FormatException('Linked database files are not supported.');
      }
    }
  }
}
