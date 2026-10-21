import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/database/bundled_database_installer.dart';
import 'package:fptu_se_brain/database/database_integrity.dart';
import 'package:fptu_se_brain/database/database_repository.dart';
import 'package:fptu_se_brain/database/flm_database_models.dart';
import 'package:fptu_se_brain/database/flm_incremental_updater.dart';
import 'package:fptu_se_brain/database/json_store.dart';
import 'package:fptu_se_brain/flm/flm_syllabus_service.dart';
import 'package:fptu_se_brain/models/curriculum_subject.dart';
import 'package:fptu_se_brain/screens/flm_database_update_screen.dart';

void main() {
  late Directory temp;
  late JsonStore store;
  late DatabaseRepository repo;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fpt-incremental-test-');
    store = JsonStore(root: Directory('${temp.path}/Database'));
    await store.writeRecord(
      'curricula',
      'BIT_SE_K18D_19A',
      curriculum('BIT_SE_K18D_19A', 'CEA201').curriculumJson(DateTime.now()),
    );
    await store.writeRecord('specializations', 'BIT_SE_K18D_19A', {
      'curriculumCode': 'BIT_SE_K18D_19A',
      'specializations': [],
    });
    await store.writeRecord(
      'subjects',
      'CEA201',
      syllabusJson(syllabus('CEA201'), DateTime.now()),
    );
    await store.writeRoot('database_index.json', {
      'curriculumCount': 1,
      'subjectCount': 1,
      'syllabusCount': 1,
      'curricula': ['BIT_SE_K18D_19A'],
      'subjects': ['CEA201'],
    });
    await store.writeRoot('release_metadata.json', {
      'databaseVersion': 1,
      'schemaVersion': 1,
      'builtAt': '2026-10-01',
    });
    await store.writeRoot('personal-preserved.json', {'untouched': true});
    repo = DatabaseRepository(store.root);
    await repo.initialize();
  });
  tearDown(() async => temp.delete(recursive: true));

  FlmIncrementalUpdater updater(
    List<String> codes, {
    CurriculumDataCallback? getCurriculum,
    Future<SyllabusDetailResult> Function(String)? getSyllabus,
  }) => FlmIncrementalUpdater(
    repo,
    discover: () async => codes,
    extractCurriculum:
        getCurriculum ?? (code) async => curriculum(code, 'PRM393'),
    extractSyllabus: getSyllabus ?? (code) async => syllabus(code),
  );

  test(
    'ID-only no-change avoids detail downloads and declares limited scope',
    () async {
      final result = await updater(
        ['BIT_SE_K18D_19A'],
        getCurriculum: (_) async => throw StateError('must not fetch'),
      ).check();
      expect(result.detailDownloads, 0);
      expect(result.added, 0);
      expect(result.message, contains('cannot be detected from IDs alone'));
      expect(result.message, isNot(contains('up to date')));
    },
  );
  test(
    'new identities merge, refresh search, preserve unseen records and restart',
    () async {
      final result = await updater(['BIT_SE_K20A']).check();
      expect(result.detailDownloads, 2);
      expect(result.added, 3);
      expect(repo.curriculumCount, 2);
      expect(repo.syllabusCount, 2);
      expect(await repo.loadSubject('CEA201'), isNotNull);
      expect((await repo.search('PRM393')).single.code, 'PRM393');
      expect(await store.readRoot('personal-preserved.json'), {
        'untouched': true,
      });
      await verifyManagedDatabase(store.root);
      final installer = BundledDatabaseInstaller(
        databaseDirectory: store.root,
        metadataLoader: () async => {
          'databaseVersion': 1,
          'databaseSha256': 'older',
        },
        assetLoader: () async =>
            throw StateError('older bundle must not be installed'),
      );
      await installer.ensureInstalled();
      expect(await repo.loadCurriculum('BIT_SE_K20A'), isNotNull);
      expect(await Directory('${store.root.path}.backup').exists(), isTrue);
    },
  );
  test(
    'deep verification updates same identity without duplicates; stable hash skips fetchedAt',
    () async {
      final first = await updater(
        ['BIT_SE_K18D_19A'],
        getCurriculum: (code) async =>
            curriculum(code, 'CEA201', name: 'Changed course'),
      ).check(verifyExisting: true);
      expect(first.modified, 1);
      expect(repo.curriculumCount, 1);
      expect(
        (await repo.search('Changed course')).single.code,
        'BIT_SE_K18D_19A',
      );
      final second = await updater(
        ['BIT_SE_K18D_19A'],
        getCurriculum: (code) async =>
            curriculum(code, 'CEA201', name: 'Changed course'),
      ).check(verifyExisting: true);
      expect(second.modified, 0);
    },
  );
  test(
    'failure leaves live DB intact; retry resumes completed curriculum',
    () async {
      var curriculumFetches = 0;
      Future<CollectedCurriculumData> fetch(String code) async {
        curriculumFetches++;
        return curriculum(code, 'PRM393');
      }

      await expectLater(
        updater(
          ['BIT_SE_K20A'],
          getCurriculum: fetch,
          getSyllabus: (_) async => throw const SocketException('offline'),
        ).check(),
        throwsA(isA<SocketException>()),
      );
      expect(repo.curriculumCount, 1);
      expect(await repo.containsCurriculum('BIT_SE_K20A'), isFalse);
      await updater(['BIT_SE_K20A'], getCurriculum: fetch).check();
      expect(curriculumFetches, 1);
      expect(repo.curriculumCount, 2);
    },
  );
  test(
    'empty/corrupt inventory and incomplete detail never replace live DB',
    () async {
      await expectLater(updater([]).check(), throwsFormatException);
      await expectLater(updater(['../BAD']).check(), throwsFormatException);
      await expectLater(
        updater(
          ['BIT_SE_K20A'],
          getCurriculum: (code) async => CollectedCurriculumData(
            code: code,
            name: 'invalid',
            totalCredits: 0,
            subjects: [],
            specializations: [],
          ),
        ).check(),
        throwsFormatException,
      );
      expect(repo.curriculumCount, 1);
    },
  );
  test(
    'corrupt checkpoint is re-fetched, never trusted or installed',
    () async {
      var fetches = 0;
      Future<CollectedCurriculumData> fetch(String code) async {
        fetches++;
        return curriculum(code, 'PRM393');
      }

      await expectLater(
        updater(
          ['BIT_SE_K20A'],
          getCurriculum: fetch,
          getSyllabus: (_) async => throw const SocketException('interrupted'),
        ).check(),
        throwsA(isA<SocketException>()),
      );
      final pending = JsonStore(
        root: Directory('${store.root.path}.flm-pending'),
      );
      final corrupted = (await pending.readLog('BIT_SE_K20A.complete.json'))!;
      (corrupted['curriculum'] as Map)['name'] = 'corrupt content';
      await pending.writeLog('BIT_SE_K20A.complete.json', corrupted);
      await updater(['BIT_SE_K20A'], getCurriculum: fetch).check();
      expect(fetches, 2);
      expect(
        (await repo.loadCurriculum('BIT_SE_K20A'))!.name,
        'Software Engineering',
      );
    },
  );
  test('smaller detail payload cannot erase existing rows', () async {
    final record = (await store.readJson(
      store.recordPath('curricula', 'BIT_SE_K18D_19A'),
    ))!;
    final subjects =
        ((record['semesters'] as List).first as Map)['subjects'] as List;
    subjects.add({
      'code': 'PRM393',
      'name': 'Mobile programming',
      'credits': 3,
      'isComboPlaceholder': false,
    });
    await store.writeRecord('curricula', 'BIT_SE_K18D_19A', record);
    await expectLater(
      updater(
        ['BIT_SE_K18D_19A'],
        getCurriculum: (code) async => curriculum(code, 'CEA201'),
      ).check(verifyExisting: true),
      throwsFormatException,
    );
    expect(
      (await store.readJson(store.recordPath('curricula', 'BIT_SE_K18D_19A')))!,
      record,
    );
  });
  test(
    'real FLM option slots stay in curriculum, never become syllabus IDs',
    () async {
      final result = await updater(
        ['LLB_EL_K21D'],
        getCurriculum: (code) async => CollectedCurriculumData(
          code: code,
          name: 'Economic Law',
          totalCredits: 145,
          subjects: [
            const CurriculumSubject(
              code: 'EL_CK*1',
              name: 'Subject 1 of Compulsory knowledge',
              semester: 7,
              credits: 3,
              prerequisite: '',
            ),
            const CurriculumSubject(
              code: 'PRM393',
              name: 'Mobile programming',
              semester: 1,
              credits: 3,
              prerequisite: '',
            ),
          ],
          specializations: [],
        ),
      ).check();
      expect(result.detailDownloads, 2);
      final loaded = (await repo.loadCurriculum('LLB_EL_K21D'))!;
      expect(
        loaded.subjects
            .singleWhere((s) => s.code == 'EL_CK*1')
            .isComboPlaceholder,
        isTrue,
      );
      expect(
        await File(
          '${store.root.path}.flm-pending/logs/LLB_EL_K21D.complete.json',
        ).exists(),
        isTrue,
      );
    },
  );
  test(
    'authenticated zero-syllabus response is explicit, never fabricated, cached until retry',
    () async {
      var attempts = 0;
      Future<SyllabusDetailResult> unavailable(String code) async {
        attempts++;
        throw FlmSyllabusUnavailable(code);
      }

      final first = await updater([
        'BIT_SE_K20A',
      ], getSyllabus: unavailable).check();
      expect(first.unavailableSubjects, ['PRM393']);
      expect(repo.curriculumCount, 2);
      expect(repo.syllabusCount, 1);
      expect(await repo.loadSubject('PRM393'), isNull);
      expect(await repo.loadSubject('CEA201'), isNotNull);
      final second = await updater([
        'BIT_SE_K20A',
      ], getSyllabus: unavailable).check();
      expect(second.detailDownloads, 0);
      expect(second.unavailableSubjects, ['PRM393']);
      expect(attempts, 1);
      final third = await updater(['BIT_SE_K20A']).check(verifyExisting: true);
      expect(third.unavailableSubjects, isEmpty);
      expect(await repo.loadSubject('PRM393'), isNotNull);
      expect(repo.curriculumCount, 2);
    },
  );
  test('interrupted directory swap recovers verified prior database', () async {
    await updater(['BIT_SE_K20A']).check();
    final active = store.root;
    await active.delete(
      recursive: true,
    ); // Simulate loss between two directory renames.
    await BundledDatabaseInstaller(
      databaseDirectory: active,
    ).recoverInterruptedInstall();
    expect(await active.exists(), isTrue);
    expect(await repo.loadSubject('CEA201'), isNotNull);
  });
  testWidgets(
    'public UI has one action and installed counts, no collector tools',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FlmDatabaseUpdateScreen(
            repository: repo,
            updater: ScreenUpdater(repo),
          ),
        ),
      );
      expect(find.textContaining('1 curricula'), findsOneWidget);
      expect(find.text('Check for Updates'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Extract All FLM'), findsNothing);
      expect(find.text('Build Release Database'), findsNothing);
      await tester.tap(find.text('Check for Updates'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('cannot be detected from IDs alone'),
        findsOneWidget,
      );
    },
  );
}

typedef CurriculumDataCallback =
    Future<CollectedCurriculumData> Function(String);

class ScreenUpdater extends FlmIncrementalUpdater {
  ScreenUpdater(super.repository);
  @override
  Future<FlmUpdateResult> check({
    bool verifyExisting = false,
    void Function(String)? onProgress,
  }) async => const FlmUpdateResult(
    0,
    0,
    1,
    0,
    1,
    100,
    Duration(milliseconds: 10),
    false,
  );
}

CollectedCurriculumData curriculum(
  String code,
  String subject, {
  String name = 'Software Engineering',
}) => CollectedCurriculumData(
  code: code,
  name: name,
  totalCredits: 145,
  subjects: [
    CurriculumSubject(
      code: subject,
      name: subject,
      semester: 1,
      credits: 3,
      prerequisite: '',
    ),
  ],
  specializations: [],
);
SyllabusDetailResult syllabus(String code) => SyllabusDetailResult(
  subjectCode: code,
  url:
      'https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?subjectCode=$code',
  syllabusName: code,
  courseNameEnglish: 'Course $code',
  credits: 3,
  minimumPassMark: 5,
  teachingMethod: 'Lecture',
  timeAllocation: '45 hours',
  prerequisite: '',
  description: 'Course details',
  studentTasks: 'Study',
  tools: 'Computer',
  materials: [],
  outcomes: [],
  assessments: [],
);
