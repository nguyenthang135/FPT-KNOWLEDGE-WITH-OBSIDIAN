import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/database/flm_database_collector.dart';
import 'package:fptu_se_brain/database/flm_database_models.dart';
import 'package:fptu_se_brain/database/json_store.dart';
import 'package:fptu_se_brain/flm/flm_syllabus_service.dart';
import 'package:fptu_se_brain/models/curriculum_subject.dart';

void main() {
  late Directory temporaryDirectory;
  late JsonStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'flm_database_collector_test_',
    );
    store = JsonStore(root: temporaryDirectory);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('deduplicates subjects and writes the database incrementally', () async {
    final syllabusCalls = <String, int>{};
    final collector = FlmDatabaseCollector(
      store: store,
      curriculumDiscoverer: () async => ['CURRICULUM_B', 'CURRICULUM_A'],
      curriculumExtractor: (code) async => _curriculum(code, 'CEA201'),
      syllabusExtractor: (code) async {
        syllabusCalls.update(code, (value) => value + 1, ifAbsent: () => 1);
        return _syllabus(code);
      },
    );

    final state = await collector.extractAll(onProgress: (_) {});

    expect(state.isComplete, isTrue);
    expect(state.curriculaCompleted, ['CURRICULUM_A', 'CURRICULUM_B']);
    expect(state.subjectsCompleted, ['CEA201']);
    expect(syllabusCalls, {'CEA201': 1});
    expect(
      await File(store.recordPath('curricula', 'CURRICULUM_A')).exists(),
      isTrue,
    );
    expect(await File(store.recordPath('subjects', 'CEA201')).exists(), isTrue);
    final subject = await store.readJson(
      store.recordPath('subjects', 'CEA201'),
    );
    expect(subject!['description'], 'Kiến trúc máy tính');
    final index = await store.readRoot('database_index.json');
    expect(index!['curriculumCount'], 2);
    expect(index['subjectCount'], 1);
    expect(index['syllabusCount'], 1);
  });

  test('pause persists state and resume skips completed curricula', () async {
    late FlmDatabaseCollector collector;
    final curriculumCalls = <String, int>{};
    collector = FlmDatabaseCollector(
      store: store,
      curriculumDiscoverer: () async => ['CURRICULUM_A', 'CURRICULUM_B'],
      curriculumExtractor: (code) async {
        curriculumCalls.update(code, (value) => value + 1, ifAbsent: () => 1);
        if (code == 'CURRICULUM_A') {
          collector.requestPause();
        }
        return _curriculum(code, code == 'CURRICULUM_A' ? 'CEA201' : 'PRF192');
      },
      syllabusExtractor: (code) async => _syllabus(code),
    );

    final paused = await collector.extractAll(onProgress: (_) {});
    expect(paused.isPaused, isTrue);
    expect(paused.curriculaCompleted, ['CURRICULUM_A']);

    final resumed = await collector.resume(onProgress: (_) {});
    expect(resumed.isComplete, isTrue);
    expect(curriculumCalls['CURRICULUM_A'], 1);
    expect(curriculumCalls['CURRICULUM_B'], 1);
    expect(resumed.subjectsCompleted, ['CEA201', 'PRF192']);
  });

  test('records an isolated syllabus failure and continues', () async {
    final attempts = <String, int>{};
    final collector = FlmDatabaseCollector(
      store: store,
      curriculumDiscoverer: () async => ['CURRICULUM_A'],
      curriculumExtractor: (code) async {
        final first = _curriculum(code, 'BAD101');
        return CollectedCurriculumData(
          code: first.code,
          name: first.name,
          totalCredits: first.totalCredits,
          subjects: [
            ...first.subjects,
            const CurriculumSubject(
              code: 'GOOD101',
              name: 'Good subject',
              semester: 1,
              credits: 3,
              prerequisite: '',
            ),
          ],
          specializations: const [],
        );
      },
      syllabusExtractor: (code) async {
        attempts.update(code, (value) => value + 1, ifAbsent: () => 1);
        if (code == 'BAD101') {
          throw StateError('Temporary FLM failure');
        }
        return _syllabus(code);
      },
    );

    final state = await collector.extractAll(onProgress: (_) {});

    expect(state.isComplete, isFalse);
    expect(state.failedSubjects, contains('BAD101'));
    expect(state.subjectsCompleted, ['GOOD101']);
    expect(attempts['BAD101'], 3);
    expect(attempts['GOOD101'], 1);
    final failures = await store.readLog('extraction_failures.json');
    expect(failures!['subjects'], contains('BAD101'));
  });

  test('rejects zero curriculum discovery and records diagnostics', () async {
    final collector = FlmDatabaseCollector(
      store: store,
      curriculumDiscoverer: () async => const [],
    );

    await expectLater(
      collector.extractAll(onProgress: (_) {}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('No curricula were discovered from FLM'),
        ),
      ),
    );
    final state = await collector.readState();
    expect(state!.isComplete, isFalse);
    expect(state.diagnostics.stage, 'Discovery failed');
    expect(state.diagnostics.codesDiscovered, 0);
  });

  test('proves known curriculum and one syllabus before expanding', () async {
    final events = <String>[];
    final collector = FlmDatabaseCollector(
      store: store,
      curriculumDiscoverer: () async => ['OTHER_CURRICULUM', 'BIT_SE_K18D_19A'],
      curriculumExtractor: (code) async {
        events.add('curriculum:$code');
        return _curriculum(
          code,
          code == 'BIT_SE_K18D_19A' ? 'CEA201' : 'PRF192',
        );
      },
      syllabusExtractor: (code) async {
        events.add('syllabus:$code');
        return _syllabus(code);
      },
    );

    await collector.extractAll(onProgress: (_) {});

    expect(events.take(2), ['curriculum:BIT_SE_K18D_19A', 'syllabus:CEA201']);
  });

  test('rejects release export for an empty database', () async {
    final collector = FlmDatabaseCollector(store: store);
    await expectLater(
      collector.buildReleaseDatabase(),
      throwsA(isA<StateError>()),
    );
  });

  test('builds a clean portable release ZIP with metadata', () async {
    final collector = FlmDatabaseCollector(
      store: store,
      curriculumDiscoverer: () async => ['CURRICULUM_A'],
      curriculumExtractor: (code) async => _curriculum(code, 'CEA201'),
      syllabusExtractor: (code) async => _syllabus(code),
    );
    await collector.extractAll(onProgress: (_) {});
    await store.writeLog('debug.json', {'secret': false});
    await File(
      '${store.recordPath('subjects', 'TEMP')}.tmp',
    ).writeAsString('{}');
    await File(
      '${store.recordPath('subjects', 'BACKUP')}.bak',
    ).writeAsString('{}');

    final zipPath =
        '${temporaryDirectory.path}${Platform.pathSeparator}release.zip';
    final result = await collector.buildReleaseDatabase(outputPath: zipPath);
    final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final names = archive.files.map((file) => file.name).toSet();

    expect(result.curriculumCount, 1);
    expect(result.subjectCount, 1);
    expect(result.syllabusCount, 1);
    expect(names, contains('Database/database_index.json'));
    expect(names, contains('Database/release_metadata.json'));
    expect(names, contains('Database/curricula/CURRICULUM_A.json'));
    expect(names, contains('Database/subjects/CEA201.json'));
    expect(names, contains('Database/specializations/CURRICULUM_A.json'));
    expect(names.any((name) => name.contains('logs/')), isFalse);
    expect(names.any((name) => name.endsWith('.tmp')), isFalse);
    expect(names.any((name) => name.endsWith('.bak')), isFalse);

    final metadataFile = archive.files.singleWhere(
      (file) => file.name == 'Database/release_metadata.json',
    );
    final metadata = String.fromCharCodes(metadataFile.content as List<int>);
    expect(metadata, contains('"curriculumCount": 1'));
    expect(metadata, contains('"syllabusCount": 1'));
  });
}

CollectedCurriculumData _curriculum(String code, String subjectCode) {
  return CollectedCurriculumData(
    code: code,
    name: 'Software Engineering',
    totalCredits: 145,
    subjects: [
      CurriculumSubject(
        code: subjectCode,
        name: 'Computer Architecture',
        semester: 1,
        credits: 3,
        prerequisite: '',
      ),
    ],
    specializations: const [],
  );
}

SyllabusDetailResult _syllabus(String code) {
  return SyllabusDetailResult(
    subjectCode: code,
    url: 'https://flm.example/$code',
    syllabusName: code,
    courseNameEnglish: 'Course $code',
    credits: 3,
    minimumPassMark: 5,
    teachingMethod: 'Lecture',
    timeAllocation: '45 hours',
    prerequisite: '',
    description: 'Kiến trúc máy tính',
    studentTasks: 'Study',
    tools: 'Computer',
    materials: const [],
    outcomes: const [],
    assessments: const [],
  );
}
