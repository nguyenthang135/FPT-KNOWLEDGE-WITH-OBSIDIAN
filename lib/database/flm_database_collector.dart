import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../flm/flm_combo_service.dart';
import '../flm/flm_session.dart';
import '../flm/flm_syllabus_service.dart';
import 'flm_database_models.dart';
import 'json_store.dart';

typedef CurriculumExtractor =
    Future<CollectedCurriculumData> Function(String code);
typedef CurriculumDiscoverer = Future<List<String>> Function();
typedef SyllabusExtractor = Future<SyllabusDetailResult> Function(String code);
typedef CollectionProgressCallback = void Function(FlmCollectionProgress value);

class FlmDatabaseCollector {
  final FlmSession session;
  final FlmComboService comboService;
  final FlmSyllabusService syllabusService;
  final JsonStore store;
  final CurriculumDiscoverer? curriculumDiscoverer;
  final CurriculumExtractor? curriculumExtractor;
  final SyllabusExtractor? syllabusExtractor;

  bool _pauseRequested = false;
  bool get pauseRequested => _pauseRequested;
  String get defaultReleasePath =>
      '${store.root.parent.path}${Platform.pathSeparator}fpt_knowledge_database.zip';

  FlmDatabaseCollector({
    FlmSession? session,
    FlmComboService? comboService,
    FlmSyllabusService? syllabusService,
    JsonStore? store,
    this.curriculumDiscoverer,
    this.curriculumExtractor,
    this.syllabusExtractor,
  }) : session = session ?? FlmSession.instance,
       comboService = comboService ?? FlmComboService(session: session),
       syllabusService =
           syllabusService ?? FlmSyllabusService(session: session),
       store = store ?? JsonStore();

  void requestPause() {
    _pauseRequested = true;
  }

  Future<Map<String, dynamic>?> readIndex() async {
    await store.initialize();
    return store.readRoot('database_index.json');
  }

  Future<FlmExtractionState?> readState() async {
    await store.initialize();
    final json = await store.readLog('extraction_state.json');
    return json == null ? null : FlmExtractionState.fromJson(json);
  }

  Future<FlmExtractionState> extractAll({
    required CollectionProgressCallback onProgress,
  }) => _collect(resume: false, onProgress: onProgress);

  Future<FlmExtractionState> updateDatabase({
    required CollectionProgressCallback onProgress,
  }) => _collect(resume: false, onProgress: onProgress);

  Future<FlmExtractionState> resume({
    required CollectionProgressCallback onProgress,
  }) => _collect(resume: true, onProgress: onProgress);

  Future<FlmExtractionState> _collect({
    required bool resume,
    required CollectionProgressCallback onProgress,
  }) async {
    await store.initialize();
    _pauseRequested = false;
    var state = resume
        ? await readState() ?? FlmExtractionState.fresh()
        : FlmExtractionState.fresh();

    if (state.curriculaDiscovered.isEmpty || !resume) {
      onProgress(
        FlmCollectionProgress(
          phase: 'Discovering curricula',
          currentItem: 'FLM curriculum catalogue',
          current: 0,
          total: 0,
          state: state,
        ),
      );
      final discovered = await _retry(
        () => curriculumDiscoverer != null
            ? curriculumDiscoverer!()
            : session.discoverCurriculumCodes(
                onDiagnostics: (value) {
                  state = state.copyWith(
                    diagnostics: state.diagnostics.copyWith(
                      currentUrl: value.currentUrl,
                      loginDetected: value.loginDetected,
                      stage: 'Discovering curricula',
                      rowsFound: value.rowsFound,
                      codesDiscovered: value.codes.length,
                    ),
                  );
                  onProgress(
                    FlmCollectionProgress(
                      phase: 'Discovering curricula',
                      currentItem: value.currentUrl,
                      current: value.codes.length,
                      total: value.resultCount ?? 0,
                      state: state,
                    ),
                  );
                },
              ),
      );
      final normalized =
          discovered
              .map((code) => code.trim().toUpperCase())
              .where((code) => code.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (normalized.isEmpty) {
        const message =
            'No curricula were discovered from FLM. '
            'Check authentication or FLM page compatibility.';
        state = state.copyWith(
          isComplete: false,
          diagnostics: state.diagnostics.copyWith(
            stage: 'Discovery failed',
            codesDiscovered: 0,
            lastError: message,
          ),
        );
        await _saveState(state);
        throw StateError(message);
      }
      const knownTarget = 'BIT_SE_K18D_19A';
      if (normalized.remove(knownTarget)) {
        normalized.insert(0, knownTarget);
      }
      state = state.copyWith(
        curriculaDiscovered: normalized,
        diagnostics: state.diagnostics.copyWith(
          stage: 'Curricula discovered',
          codesDiscovered: normalized.length,
          lastError: '',
        ),
      );
      await _saveState(state);
    }

    final subjectCodes = state.subjectsDiscovered.toSet();
    final completedCurricula = state.curriculaCompleted.toSet();
    final curriculumFailures = Map<String, String>.from(state.failedCurricula);

    const knownTarget = 'BIT_SE_K18D_19A';
    if (state.curriculaDiscovered.contains(knownTarget) &&
        !completedCurricula.contains(knownTarget)) {
      state = state.copyWith(
        diagnostics: state.diagnostics.copyWith(
          stage: 'Proving known curriculum',
          currentCurriculum: knownTarget,
          currentSubject: '',
          lastError: '',
        ),
      );
      onProgress(
        FlmCollectionProgress(
          phase: 'Proving known curriculum',
          currentItem: knownTarget,
          current: 1,
          total: state.curriculaDiscovered.length,
          state: state,
        ),
      );
      try {
        final data = await _retry(() => _extractCurriculum(knownTarget));
        final fetchedAt = DateTime.now();
        await store.writeRecord(
          'curricula',
          knownTarget,
          data.curriculumJson(fetchedAt),
        );
        await store.writeRecord(
          'specializations',
          knownTarget,
          data.specializationsJson(fetchedAt),
        );
        subjectCodes.addAll(data.uniqueSubjectCodes);
        completedCurricula.add(knownTarget);
        curriculumFailures.remove(knownTarget);
        state = state.copyWith(
          curriculaCompleted: _sorted(completedCurricula),
          subjectsDiscovered: _sorted(subjectCodes),
          failedCurricula: curriculumFailures,
        );
        await _saveState(state);
      } catch (error) {
        curriculumFailures[knownTarget] = error.toString();
        state = state.copyWith(
          failedCurricula: curriculumFailures,
          diagnostics: state.diagnostics.copyWith(lastError: error.toString()),
        );
        await _saveState(state);
        throw StateError(
          'Known curriculum proof failed for $knownTarget: $error',
        );
      }
    }

    if (completedCurricula.contains(knownTarget) &&
        state.subjectsCompleted.isEmpty &&
        subjectCodes.isNotEmpty) {
      final proofSubject = subjectCodes.contains('CEA201')
          ? 'CEA201'
          : (_sorted(subjectCodes).first);
      state = state.copyWith(
        diagnostics: state.diagnostics.copyWith(
          stage: 'Proving real syllabus',
          currentCurriculum: knownTarget,
          currentSubject: proofSubject,
          lastError: '',
        ),
      );
      onProgress(
        FlmCollectionProgress(
          phase: 'Proving real syllabus',
          currentItem: proofSubject,
          current: 1,
          total: subjectCodes.length,
          state: state,
        ),
      );
      try {
        final syllabus = await _retry(
          () => syllabusExtractor != null
              ? syllabusExtractor!(proofSubject)
              : syllabusService.loadExactSyllabus(proofSubject),
        );
        await store.writeRecord(
          'subjects',
          proofSubject,
          syllabusJson(syllabus, DateTime.now()),
        );
        final completed = {...state.subjectsCompleted, proofSubject};
        final failures = Map<String, String>.from(state.failedSubjects)
          ..remove(proofSubject);
        state = state.copyWith(
          subjectsCompleted: _sorted(completed),
          failedSubjects: failures,
        );
        await _saveState(state);
      } catch (error) {
        final failures = Map<String, String>.from(state.failedSubjects)
          ..[proofSubject] = error.toString();
        state = state.copyWith(
          failedSubjects: failures,
          diagnostics: state.diagnostics.copyWith(lastError: error.toString()),
        );
        await _saveState(state);
        throw StateError(
          'Real syllabus proof failed for $proofSubject: $error',
        );
      }
    }

    for (var index = 0; index < state.curriculaDiscovered.length; index++) {
      final code = state.curriculaDiscovered[index];
      if (completedCurricula.contains(code)) {
        continue;
      }
      if (_pauseRequested) {
        return _pause(
          state,
          subjectCodes,
          completedCurricula,
          curriculumFailures,
        );
      }

      onProgress(
        FlmCollectionProgress(
          phase: 'Extracting curricula',
          currentItem: code,
          current: index + 1,
          total: state.curriculaDiscovered.length,
          state: state,
        ),
      );
      state = state.copyWith(
        diagnostics: state.diagnostics.copyWith(
          stage: 'Extracting curricula',
          currentCurriculum: code,
          currentSubject: '',
          lastError: '',
        ),
      );

      try {
        final data = await _retry(() => _extractCurriculum(code));
        final fetchedAt = DateTime.now();
        await store.writeRecord(
          'curricula',
          code,
          data.curriculumJson(fetchedAt),
        );
        await store.writeRecord(
          'specializations',
          code,
          data.specializationsJson(fetchedAt),
        );
        subjectCodes.addAll(data.uniqueSubjectCodes);
        completedCurricula.add(code);
        curriculumFailures.remove(code);
      } catch (error) {
        curriculumFailures[code] = error.toString();
        state = state.copyWith(
          diagnostics: state.diagnostics.copyWith(lastError: error.toString()),
        );
      }

      state = state.copyWith(
        curriculaCompleted: _sorted(completedCurricula),
        subjectsDiscovered: _sorted(subjectCodes),
        failedCurricula: curriculumFailures,
        isComplete: false,
        isPaused: false,
      );
      await _saveState(state);
    }

    final completedSubjects = state.subjectsCompleted.toSet();
    final subjectFailures = Map<String, String>.from(state.failedSubjects);
    final orderedSubjects = _sorted(subjectCodes);

    for (var index = 0; index < orderedSubjects.length; index++) {
      final code = orderedSubjects[index];
      if (completedSubjects.contains(code)) {
        continue;
      }
      if (_pauseRequested) {
        state = state.copyWith(
          curriculaCompleted: _sorted(completedCurricula),
          subjectsDiscovered: orderedSubjects,
          subjectsCompleted: _sorted(completedSubjects),
          failedCurricula: curriculumFailures,
          failedSubjects: subjectFailures,
          isPaused: true,
          isComplete: false,
        );
        await _saveState(state);
        await _rebuildIndex(state);
        return state;
      }

      onProgress(
        FlmCollectionProgress(
          phase: 'Extracting syllabi',
          currentItem: code,
          current: index + 1,
          total: orderedSubjects.length,
          state: state,
        ),
      );
      state = state.copyWith(
        diagnostics: state.diagnostics.copyWith(
          stage: 'Extracting syllabi',
          currentCurriculum: '',
          currentSubject: code,
          lastError: '',
        ),
      );

      try {
        final syllabus = await _retry(
          () => syllabusExtractor != null
              ? syllabusExtractor!(code)
              : syllabusService.loadExactSyllabus(code),
        );
        await store.writeRecord(
          'subjects',
          code,
          syllabusJson(syllabus, DateTime.now()),
        );
        completedSubjects.add(code);
        subjectFailures.remove(code);
      } catch (error) {
        subjectFailures[code] = error.toString();
        state = state.copyWith(
          diagnostics: state.diagnostics.copyWith(lastError: error.toString()),
        );
      }

      state = state.copyWith(
        subjectsDiscovered: orderedSubjects,
        subjectsCompleted: _sorted(completedSubjects),
        failedCurricula: curriculumFailures,
        failedSubjects: subjectFailures,
        isComplete: false,
        isPaused: false,
      );
      await _saveState(state);
    }

    final complete =
        curriculumFailures.isEmpty &&
        subjectFailures.isEmpty &&
        completedCurricula.length == state.curriculaDiscovered.length &&
        completedSubjects.length == orderedSubjects.length;
    state = state.copyWith(
      curriculaCompleted: _sorted(completedCurricula),
      subjectsDiscovered: orderedSubjects,
      subjectsCompleted: _sorted(completedSubjects),
      failedCurricula: curriculumFailures,
      failedSubjects: subjectFailures,
      isComplete: complete,
      isPaused: false,
      diagnostics: state.diagnostics.copyWith(
        stage: complete ? 'Complete' : 'Finished with failures',
        currentCurriculum: '',
        currentSubject: '',
      ),
    );
    await _saveState(state);
    await _rebuildIndex(state);
    onProgress(
      FlmCollectionProgress(
        phase: complete ? 'Complete' : 'Finished with failures',
        currentItem: '',
        current: completedSubjects.length,
        total: orderedSubjects.length,
        state: state,
      ),
    );
    return state;
  }

  Future<CollectedCurriculumData> _extractCurriculum(String code) async {
    if (curriculumExtractor != null) {
      return curriculumExtractor!(code);
    }

    await session.searchCurriculum(code);
    await session.openCurriculumByCode(code);
    final metadata = await session.getCurriculumMetadata();
    final subjects = await session.getCurriculumSubjects();
    final name = metadata['name']?.toString().trim() ?? '';
    final totalCreditsText = metadata['totalCredits']?.toString() ?? '';
    final totalCredits = int.tryParse(
      RegExp(r'\d+').firstMatch(totalCreditsText)?.group(0) ?? '',
    );

    final baseData = CollectedCurriculumData(
      code: code,
      name: name.isEmpty ? null : name,
      totalCredits: totalCredits,
      subjects: subjects,
      specializations: const [],
    );
    await store.writeRecord(
      'curricula',
      code,
      baseData.curriculumJson(DateTime.now()),
    );

    final specializations = <SpecializationCombo>[];
    if (subjects.any((subject) => subject.isComboPlaceholder)) {
      final options = await comboService.loadAvailableCombos(code);
      for (final option in options) {
        specializations.add(await comboService.loadCombo(option));
      }
    }

    return CollectedCurriculumData(
      code: code,
      name: baseData.name,
      totalCredits: totalCredits,
      subjects: subjects,
      specializations: specializations,
    );
  }

  Future<T> _retry<T>(Future<T> Function() operation) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: attempt * 750));
        }
      }
    }
    throw lastError!;
  }

  Future<FlmExtractionState> _pause(
    FlmExtractionState state,
    Set<String> subjectCodes,
    Set<String> completedCurricula,
    Map<String, String> curriculumFailures,
  ) async {
    final paused = state.copyWith(
      curriculaCompleted: _sorted(completedCurricula),
      subjectsDiscovered: _sorted(subjectCodes),
      failedCurricula: curriculumFailures,
      isPaused: true,
      isComplete: false,
    );
    await _saveState(paused);
    await _rebuildIndex(paused);
    return paused;
  }

  Future<void> _saveState(FlmExtractionState state) async {
    await store.writeLog('extraction_state.json', state.toJson());
    await store.writeLog('extraction_failures.json', {
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'curricula': state.failedCurricula,
      'subjects': state.failedSubjects,
      'runError': state.diagnostics.lastError,
      'diagnostics': state.diagnostics.toJson(),
    });
  }

  Future<ReleaseDatabaseResult> buildReleaseDatabase({
    String? outputPath,
  }) async {
    await store.initialize();
    final savedState = await readState();
    if (savedState != null && savedState.curriculaCompleted.isNotEmpty) {
      await _rebuildIndex(savedState);
    }
    final index = await store.readRoot('database_index.json');
    if (index == null) {
      throw StateError(
        'Cannot build release database: database_index.json is missing or invalid.',
      );
    }

    final curricula = await _readReleaseFiles('curricula');
    final subjects = await _readReleaseFiles('subjects');
    final specializations = await _readReleaseFiles('specializations');
    final curriculumCount = curricula.length;
    final syllabusCount = subjects.length;
    final subjectCount =
        int.tryParse(index['subjectCount']?.toString() ?? '') ?? 0;
    if (curriculumCount == 0 || subjectCount == 0 || syllabusCount == 0) {
      throw StateError(
        'Cannot build release database: the database must contain at least one '
        'readable curriculum and subject syllabus.',
      );
    }

    final metadata = <String, dynamic>{
      'databaseVersion': 1,
      'schemaVersion': 1,
      'builtAt': DateTime.now().toUtc().toIso8601String(),
      'curriculumCount': curriculumCount,
      'subjectCount': subjectCount,
      'syllabusCount': syllabusCount,
      'source': 'FPT Learning Materials',
    };
    final archive = Archive();
    void addJson(String name, Map<String, dynamic> value) {
      final bytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(value),
      );
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addJson('Database/database_index.json', index);
    addJson('Database/release_metadata.json', metadata);
    for (final entry in curricula.entries) {
      addJson('Database/curricula/${entry.key}', entry.value);
    }
    for (final entry in subjects.entries) {
      addJson('Database/subjects/${entry.key}', entry.value);
    }
    for (final entry in specializations.entries) {
      addJson('Database/specializations/${entry.key}', entry.value);
    }

    final targetPath = outputPath ?? defaultReleasePath;
    final temporaryPath = '$targetPath.tmp';
    final encoded = ZipEncoder().encode(archive);
    final temporaryFile = File(temporaryPath);
    await temporaryFile.parent.create(recursive: true);
    await temporaryFile.writeAsBytes(encoded, flush: true);
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    await temporaryFile.rename(targetPath);
    return ReleaseDatabaseResult(
      zipPath: targetPath,
      curriculumCount: curriculumCount,
      subjectCount: subjectCount,
      syllabusCount: syllabusCount,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _readReleaseFiles(
    String directory,
  ) async {
    final result = <String, Map<String, dynamic>>{};
    final folder = Directory(store.directoryPath(directory));
    if (!await folder.exists()) return result;
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final json = await store.readJson(entity.path);
      if (json != null) {
        result[entity.uri.pathSegments.last] = json;
      }
    }
    return result;
  }

  Future<void> _rebuildIndex(FlmExtractionState state) async {
    final curriculumRecords = await store.readRecords('curricula');
    final subjectRecords = await store.readRecords('subjects');
    final specializationRecords = await store.readRecords('specializations');
    final curricula =
        curriculumRecords
            .map((json) => json['code']?.toString() ?? '')
            .where((code) => code.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final subjects =
        subjectRecords
            .map((json) => json['code']?.toString() ?? '')
            .where((code) => code.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final specializationCount = specializationRecords.where((json) {
      final values = json['specializations'];
      return values is List && values.isNotEmpty;
    }).length;

    await store.writeRoot('database_index.json', {
      'version': 1,
      'lastUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      'curriculumCount': curricula.length,
      'subjectCount': state.subjectsDiscovered.length,
      'syllabusCount': subjects.length,
      'specializationCurriculumCount': specializationCount,
      'curricula': curricula,
      'subjects': subjects,
    });
  }

  List<String> _sorted(Iterable<String> values) {
    return values.toSet().toList()..sort();
  }
}
