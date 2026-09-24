import 'dart:convert';
import 'dart:io';

import '../flm/flm_combo_service.dart';
import '../flm/flm_syllabus_service.dart';
import '../models/curriculum_subject.dart';
import '../vault/vault_picker.dart';

typedef ObsidianProgressCallback =
    void Function(int current, int total, String message);

class ObsidianExportResult {
  final String vaultPath;
  final String curriculumPath;
  final bool looksLikeObsidianVault;
  final int exportedSubjects;
  final List<String> failedSubjects;

  const ObsidianExportResult({
    required this.vaultPath,
    required this.curriculumPath,
    required this.looksLikeObsidianVault,
    required this.exportedSubjects,
    required this.failedSubjects,
  });
}

class ObsidianSyncInspection {
  final bool folderAvailable;
  final bool needsSync;
  final String message;

  const ObsidianSyncInspection({
    required this.folderAvailable,
    required this.needsSync,
    required this.message,
  });
}

class _SyncState {
  final String? specializationName;
  final List<String> specializationSubjectCodes;

  const _SyncState({
    required this.specializationName,
    required this.specializationSubjectCodes,
  });

  factory _SyncState.fromJson(Map<String, dynamic> json) {
    final rawCodes = json['specializationSubjectCodes'];

    return _SyncState(
      specializationName: json['specializationName']?.toString().trim(),
      specializationSubjectCodes: rawCodes is List
          ? rawCodes
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'specializationName': specializationName,
      'specializationSubjectCodes': specializationSubjectCodes,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class ObsidianService {
  final VaultPicker _picker = const VaultPicker();

  final FlmSyllabusService _syllabusService = FlmSyllabusService();

  // ==================================================
  // REMEMBERED VAULT
  // ==================================================

  Future<String?> getSavedVaultPath() async {
    try {
      final file = await _settingsFile();

      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();

      final decoded = jsonDecode(content);

      if (decoded is! Map) {
        return null;
      }

      final path = decoded['vaultPath']?.toString().trim() ?? '';

      if (path.isEmpty) {
        return null;
      }

      final directory = Directory(path);

      if (!await directory.exists()) {
        return null;
      }

      return directory.path;
    } catch (_) {
      return null;
    }
  }

  Future<ObsidianSyncInspection> inspectCurriculumSync({
    required String knowledgeFolderPath,
    required String curriculumCode,
    required SpecializationCombo? specialization,
  }) async {
    final selectedDirectory = Directory(knowledgeFolderPath.trim());

    if (!await selectedDirectory.exists()) {
      return const ObsidianSyncInspection(
        folderAvailable: false,
        needsSync: true,
        message:
            'The selected knowledge folder no longer exists. Choose another folder.',
      );
    }

    final curriculumRoot = Directory(
      _join(
        _join(selectedDirectory.path, 'FPT Knowledge'),
        _safeName(curriculumCode),
      ),
    );

    if (!await curriculumRoot.exists()) {
      return const ObsidianSyncInspection(
        folderAvailable: true,
        needsSync: true,
        message:
            'The current curriculum has not been generated in this knowledge folder.',
      );
    }

    final manifest = File(
      _join(curriculumRoot.path, '.fpt_knowledge_sync.json'),
    );

    final state = await _readSyncState(manifest);

    if (state == null) {
      return const ObsidianSyncInspection(
        folderAvailable: true,
        needsSync: true,
        message: 'The local sync record is missing or unreadable.',
      );
    }

    final generatedStructureIsUsable = await _hasUsableGeneratedStructure(
      curriculumRoot: curriculumRoot,
      specialization: specialization,
    );

    if (!generatedStructureIsUsable) {
      return const ObsidianSyncInspection(
        folderAvailable: true,
        needsSync: true,
        message:
            'The local sync record exists, but required generated files are missing.',
      );
    }

    final expectedName = specialization?.name.trim().toLowerCase();
    final actualName = state.specializationName?.trim().toLowerCase();

    final expectedCodes =
        specialization?.subjects
            .map((subject) => _subjectKey(subject.code))
            .toSet() ??
        <String>{};
    final actualCodes = state.specializationSubjectCodes
        .map(_subjectKey)
        .toSet();

    final specializationMatches =
        expectedName == actualName &&
        expectedCodes.length == actualCodes.length &&
        expectedCodes.containsAll(actualCodes);

    if (!specializationMatches) {
      return const ObsidianSyncInspection(
        folderAvailable: true,
        needsSync: true,
        message:
            'The generated knowledge folder does not match the current specialization.',
      );
    }

    return const ObsidianSyncInspection(
      folderAvailable: true,
      needsSync: false,
      message: 'The local knowledge folder and sync record are usable.',
    );
  }

  Future<bool> _hasUsableGeneratedStructure({
    required Directory curriculumRoot,
    required SpecializationCombo? specialization,
  }) async {
    final curriculumIndex = File(_join(curriculumRoot.path, 'Curriculum.md'));
    final semestersDirectory = Directory(
      _join(curriculumRoot.path, 'Semesters'),
    );
    final subjectsDirectory = Directory(_join(curriculumRoot.path, 'Subjects'));

    if (!await curriculumIndex.exists() ||
        !await semestersDirectory.exists() ||
        !await subjectsDirectory.exists()) {
      return false;
    }

    var hasSemesterPage = false;
    await for (final entity in semestersDirectory.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        hasSemesterPage = true;
        break;
      }
    }

    if (!hasSemesterPage) {
      return false;
    }

    var hasSubject = false;
    await for (final entity in subjectsDirectory.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }

      if (await _hasGeneratedSubjectFiles(entity)) {
        hasSubject = true;
      } else if (await _hasAnyGeneratedSubjectFile(entity)) {
        return false;
      }
    }

    if (!hasSubject) {
      return false;
    }

    if (specialization != null) {
      final specializationPage = File(
        _join(
          _join(curriculumRoot.path, 'Specialization'),
          '${_safeName(specialization.name)}.md',
        ),
      );

      if (!await specializationPage.exists()) {
        return false;
      }

      for (final subject in specialization.subjects) {
        final subjectDirectory = Directory(
          _join(subjectsDirectory.path, _safeName(subject.code)),
        );
        if (!await subjectDirectory.exists() ||
            !await _hasGeneratedSubjectFiles(subjectDirectory)) {
          return false;
        }
      }
    }

    return true;
  }

  Future<bool> _hasGeneratedSubjectFiles(Directory subjectDirectory) async {
    for (final filename in const [
      'Overview.md',
      'Assessment.md',
      'Materials.md',
    ]) {
      if (!await File(_join(subjectDirectory.path, filename)).exists()) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _hasAnyGeneratedSubjectFile(Directory subjectDirectory) async {
    for (final filename in const [
      'Overview.md',
      'Assessment.md',
      'Materials.md',
    ]) {
      if (await File(_join(subjectDirectory.path, filename)).exists()) {
        return true;
      }
    }

    return false;
  }

  Future<String?> chooseVault() async {
    final selectedPath = await _picker.pickDirectory();

    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return null;
    }

    final directory = Directory(selectedPath.trim());

    if (!await directory.exists()) {
      throw Exception('Selected folder does not exist.');
    }

    await _saveVaultPath(directory.path);

    return directory.path;
  }

  Future<void> forgetVault() async {
    final file = await _settingsFile();

    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _settingsFile() async {
    final appData = Platform.environment['APPDATA'] ?? Directory.current.path;

    final directory = Directory(_join(appData, 'FPT Knowledge'));

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return File(_join(directory.path, 'settings.json'));
  }

  Future<void> _saveVaultPath(String path) async {
    final file = await _settingsFile();

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'vaultPath': path}),
      flush: true,
    );
  }

  // ==================================================
  // EXPORT
  // ==================================================

  Future<ObsidianExportResult?> exportCurriculum({
    required String curriculumCode,
    required List<CurriculumSubject> curriculumSubjects,
    required SpecializationCombo? specialization,
    bool chooseNewVault = false,
    ObsidianProgressCallback? onProgress,
  }) async {
    String? selectedPath;

    if (!chooseNewVault) {
      selectedPath = await getSavedVaultPath();
    }

    selectedPath ??= await chooseVault();

    if (selectedPath == null) {
      return null;
    }

    final vaultDirectory = Directory(selectedPath);

    if (!await vaultDirectory.exists()) {
      throw Exception('The saved Obsidian vault no longer exists.');
    }

    await _saveVaultPath(vaultDirectory.path);

    final obsidianConfigDirectory = Directory(
      _join(vaultDirectory.path, '.obsidian'),
    );

    final looksLikeObsidianVault = await obsidianConfigDirectory.exists();

    final safeCurriculumCode = _safeName(curriculumCode);

    final fptRoot = Directory(_join(vaultDirectory.path, 'FPT Knowledge'));

    final curriculumRoot = Directory(_join(fptRoot.path, safeCurriculumCode));

    final semestersDirectory = Directory(
      _join(curriculumRoot.path, 'Semesters'),
    );

    final subjectsDirectory = Directory(_join(curriculumRoot.path, 'Subjects'));

    final specializationDirectory = Directory(
      _join(curriculumRoot.path, 'Specialization'),
    );

    final archiveDirectory = Directory(
      _join(curriculumRoot.path, 'Archived Specialization'),
    );

    await curriculumRoot.create(recursive: true);

    await semestersDirectory.create(recursive: true);

    await subjectsDirectory.create(recursive: true);

    if (specialization != null) {
      await specializationDirectory.create(recursive: true);
    }

    // ==================================================
    // BASE CURRICULUM
    // ==================================================

    final baseSubjects = curriculumSubjects
        .where((subject) => !subject.isComboPlaceholder)
        .toList();

    final baseSubjectKeys = baseSubjects
        .map((subject) => _subjectKey(subject.code))
        .toSet();

    // ==================================================
    // CURRENT SPECIALIZATION
    // ==================================================

    final currentSpecializationCodes =
        specialization?.subjects.map((subject) => subject.code).toList() ??
        <String>[];

    final currentSpecializationKeys = currentSpecializationCodes
        .map(_subjectKey)
        .toSet();

    final currentSpecializationName = specialization?.name.trim();

    // ==================================================
    // READ PREVIOUS SYNC STATE
    // ==================================================

    final manifestFile = File(
      _join(curriculumRoot.path, '.fpt_knowledge_sync.json'),
    );

    final previousState = await _readSyncState(manifestFile);

    String? previousSpecializationName = previousState?.specializationName;

    Set<String> previousSpecializationKeys;

    if (previousState != null) {
      previousSpecializationKeys = previousState.specializationSubjectCodes
          .map(_subjectKey)
          .toSet();
    } else {
      previousSpecializationKeys = await _inferOldSpecializationSubjects(
        subjectsDirectory: subjectsDirectory,
        baseSubjectKeys: baseSubjectKeys,
      );

      previousSpecializationName ??= await _inferOldSpecializationName(
        specializationDirectory: specializationDirectory,
        currentSpecializationName: currentSpecializationName,
      );
    }

    // ==================================================
    // FIND OLD SUBJECTS THAT ARE NO LONGER ACTIVE
    // ==================================================

    final staleSpecializationKeys = previousSpecializationKeys
        .difference(currentSpecializationKeys)
        .where((key) => !baseSubjectKeys.contains(key))
        .toSet();

    final specializationNameChanged =
        previousSpecializationName != null &&
        previousSpecializationName.trim().isNotEmpty &&
        (currentSpecializationName == null ||
            previousSpecializationName.trim().toLowerCase() !=
                currentSpecializationName.trim().toLowerCase());

    // ==================================================
    // ARCHIVE OLD SPECIALIZATION PERSONAL NOTES
    // ==================================================

    if (specializationNameChanged) {
      await _archiveSpecializationNotes(
        specializationDirectory: specializationDirectory,
        archiveDirectory: archiveDirectory,
        oldSpecializationName: previousSpecializationName,
      );
    }

    // ==================================================
    // REMOVE / ARCHIVE OLD SPECIALIZATION SUBJECTS
    // ==================================================

    for (final staleKey in staleSpecializationKeys) {
      await _retireSpecializationSubject(
        subjectsDirectory: subjectsDirectory,
        archiveDirectory: archiveDirectory,
        oldSpecializationName: previousSpecializationName,
        subjectKey: staleKey,
      );
    }

    await _removeOldGeneratedSpecializationPages(
      specializationDirectory: specializationDirectory,
      currentSpecializationName: currentSpecializationName,
    );

    // ==================================================
    // RESTORE NOTES IF USER SWITCHES BACK
    // ==================================================

    if (specialization != null) {
      await _restoreSpecializationNotes(
        specializationDirectory: specializationDirectory,
        archiveDirectory: archiveDirectory,
        specializationName: specialization.name,
      );
    }

    // ==================================================
    // BUILD CURRENT ACTIVE STUDY PLAN
    // ==================================================

    final subjectMap = <String, CurriculumSubject>{};

    for (final subject in baseSubjects) {
      subjectMap[_subjectKey(subject.code)] = subject;
    }

    if (specialization != null) {
      for (final comboSubject in specialization.subjects) {
        final subject = CurriculumSubject(
          code: comboSubject.code,
          name: comboSubject.name,
          semester: comboSubject.semester,
          credits: 0,
          prerequisite: '',
        );

        subjectMap[_subjectKey(subject.code)] = subject;
      }
    }

    final subjects = subjectMap.values.toList()
      ..sort((a, b) {
        final semesterCompare = a.semester.compareTo(b.semester);

        if (semesterCompare != 0) {
          return semesterCompare;
        }

        return a.code.compareTo(b.code);
      });

    // ==================================================
    // IMPORTANT LINK FIX
    // ==================================================
    //
    // Obsidian already treats the selected folder as the
    // vault root.
    //
    // Therefore links must start from:
    //
    // BIT_SE_K18D_19A/Subjects/CEA201/Overview
    //
    // NOT:
    //
    // FPT Knowledge/BIT_SE_K18D_19A/Subjects/CEA201/Overview
    //
    // The old version added "FPT Knowledge/" twice and
    // caused Obsidian to open blank notes.
    //
    final vaultRelativeRoot = safeCurriculumCode;

    // ==================================================
    // CURRICULUM INDEX
    // ==================================================

    await _writeGeneratedFile(
      File(_join(curriculumRoot.path, 'Curriculum.md')),
      _buildCurriculumIndex(
        curriculumCode: curriculumCode,
        subjects: subjects,
        specialization: specialization,
        vaultRelativeRoot: vaultRelativeRoot,
      ),
    );

    // ==================================================
    // SEMESTER FILES
    // ==================================================

    final semesterNumbers =
        subjects.map((subject) => subject.semester).toSet().toList()..sort();

    for (final semester in semesterNumbers) {
      final semesterSubjects = subjects
          .where((subject) => subject.semester == semester)
          .toList();

      final filename = _semesterFilename(semester);

      await _writeGeneratedFile(
        File(_join(semestersDirectory.path, '$filename.md')),
        _buildSemesterMarkdown(
          semester: semester,
          subjects: semesterSubjects,
          specialization: specialization,
          vaultRelativeRoot: vaultRelativeRoot,
        ),
      );
    }

    // ==================================================
    // SPECIALIZATION PAGE
    // ==================================================

    if (specialization != null) {
      final specializationFileName = _safeName(
        specialization.name.isEmpty ? 'Specialization' : specialization.name,
      );

      await _writeGeneratedFile(
        File(_join(specializationDirectory.path, '$specializationFileName.md')),
        _buildSpecializationMarkdown(
          combo: specialization,
          vaultRelativeRoot: vaultRelativeRoot,
        ),
      );

      final personalSpecializationNotes = File(
        _join(specializationDirectory.path, 'My Specialization Notes.md'),
      );

      if (!await personalSpecializationNotes.exists()) {
        await personalSpecializationNotes.writeAsString('''
# My Specialization Notes

> This file belongs to you.
> FPT Knowledge will never overwrite it.

## Goals


## Important Concepts


## Career Notes


## Projects


''', flush: true);
      }
    }

    // ==================================================
    // SUBJECT FILES
    // ==================================================

    final failedSubjects = <String>[];

    var exportedSubjects = 0;

    for (var index = 0; index < subjects.length; index++) {
      final subject = subjects[index];

      onProgress?.call(
        index + 1,
        subjects.length,
        'Loading ${subject.code} from FLM...',
      );

      final subjectKey = _subjectKey(subject.code);

      final isCurrentSpecializationSubject = currentSpecializationKeys.contains(
        subjectKey,
      );

      final safeSubjectCode = _safeName(subject.code);

      final subjectDirectory = Directory(
        _join(subjectsDirectory.path, safeSubjectCode),
      );

      if (isCurrentSpecializationSubject &&
          specialization != null &&
          !await subjectDirectory.exists()) {
        await _restoreArchivedSubject(
          activeSubjectDirectory: subjectDirectory,
          archiveDirectory: archiveDirectory,
          specializationName: specialization.name,
          subjectCode: subject.code,
        );
      }

      await subjectDirectory.create(recursive: true);

      SyllabusDetailResult? syllabus;

      try {
        syllabus = await _syllabusService.loadExactSyllabus(subject.code);
      } catch (_) {
        failedSubjects.add(subject.code);
      }

      // ------------------------------------------------
      // APP-OWNED FILES
      // ------------------------------------------------

      await _writeGeneratedFile(
        File(_join(subjectDirectory.path, 'Overview.md')),
        _buildOverviewMarkdown(
          subject: subject,
          syllabus: syllabus,
          vaultRelativeRoot: vaultRelativeRoot,
        ),
      );

      await _writeGeneratedFile(
        File(_join(subjectDirectory.path, 'Assessment.md')),
        _buildAssessmentMarkdown(subject: subject, syllabus: syllabus),
      );

      await _writeGeneratedFile(
        File(_join(subjectDirectory.path, 'Materials.md')),
        _buildMaterialsMarkdown(subject: subject, syllabus: syllabus),
      );

      // ------------------------------------------------
      // USER-OWNED FILE
      // ------------------------------------------------

      final notesFile = File(_join(subjectDirectory.path, 'My Notes.md'));

      if (!await notesFile.exists()) {
        await notesFile.writeAsString(
          _buildMyNotesMarkdown(subject),
          flush: true,
        );
      }

      exportedSubjects++;
    }

    // ==================================================
    // SAVE SYNC STATE
    // ==================================================

    await _writeSyncState(
      manifestFile,
      _SyncState(
        specializationName: specialization?.name,
        specializationSubjectCodes: currentSpecializationCodes,
      ),
    );

    onProgress?.call(
      subjects.length,
      subjects.length,
      'Obsidian sync complete.',
    );

    return ObsidianExportResult(
      vaultPath: vaultDirectory.path,
      curriculumPath: curriculumRoot.path,
      looksLikeObsidianVault: looksLikeObsidianVault,
      exportedSubjects: exportedSubjects,
      failedSubjects: failedSubjects,
    );
  }

  // ==================================================
  // CLEAN SPECIALIZATION SYNC
  // ==================================================

  Future<_SyncState?> _readSyncState(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }

      final text = await file.readAsString();

      final decoded = jsonDecode(text);

      if (decoded is Map) {
        return _SyncState.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}

    return null;
  }

  Future<void> _writeSyncState(File file, _SyncState state) async {
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
  }

  Future<Set<String>> _inferOldSpecializationSubjects({
    required Directory subjectsDirectory,
    required Set<String> baseSubjectKeys,
  }) async {
    final result = <String>{};

    if (!await subjectsDirectory.exists()) {
      return result;
    }

    await for (final entity in subjectsDirectory.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }

      final folderName = _basename(entity.path);

      final key = _subjectKey(folderName);

      if (baseSubjectKeys.contains(key)) {
        continue;
      }

      final overview = File(_join(entity.path, 'Overview.md'));

      if (await _isGeneratedFile(overview)) {
        result.add(key);
      }
    }

    return result;
  }

  Future<String?> _inferOldSpecializationName({
    required Directory specializationDirectory,
    required String? currentSpecializationName,
  }) async {
    if (!await specializationDirectory.exists()) {
      return null;
    }

    final candidates = <String>[];

    await for (final entity in specializationDirectory.list(
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      final filename = _basename(entity.path);

      if (filename.toLowerCase() == 'my specialization notes.md') {
        continue;
      }

      if (!filename.toLowerCase().endsWith('.md')) {
        continue;
      }

      if (!await _isGeneratedFile(entity)) {
        continue;
      }

      candidates.add(_withoutMd(filename));
    }

    if (candidates.isEmpty) {
      return null;
    }

    if (currentSpecializationName != null) {
      final currentSafe = _safeName(currentSpecializationName).toLowerCase();

      for (final candidate in candidates) {
        if (_safeName(candidate).toLowerCase() != currentSafe) {
          return candidate;
        }
      }
    }

    return candidates.first;
  }

  Future<void> _retireSpecializationSubject({
    required Directory subjectsDirectory,
    required Directory archiveDirectory,
    required String? oldSpecializationName,
    required String subjectKey,
  }) async {
    final source = Directory(
      _join(subjectsDirectory.path, _safeName(subjectKey)),
    );

    if (!await source.exists()) {
      return;
    }

    final containsUserData = await _containsUserOwnedData(source);

    if (!containsUserData) {
      await source.delete(recursive: true);

      return;
    }

    final archiveName =
        oldSpecializationName != null && oldSpecializationName.trim().isNotEmpty
        ? oldSpecializationName
        : 'Previous Specialization';

    final archiveSpecialization = Directory(
      _join(archiveDirectory.path, _safeName(archiveName)),
    );

    await archiveSpecialization.create(recursive: true);

    final desiredDestination = _join(
      archiveSpecialization.path,
      _safeName(subjectKey),
    );

    final destination = await _uniqueDirectoryPath(desiredDestination);

    await _moveDirectory(source, Directory(destination));
  }

  Future<bool> _containsUserOwnedData(Directory directory) async {
    if (!await directory.exists()) {
      return false;
    }

    const generatedFiles = <String>{
      'overview.md',
      'assessment.md',
      'materials.md',
    };

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        return true;
      }

      final name = _basename(entity.path).toLowerCase();

      if (!generatedFiles.contains(name)) {
        return true;
      }
    }

    return false;
  }

  Future<void> _archiveSpecializationNotes({
    required Directory specializationDirectory,
    required Directory archiveDirectory,
    required String oldSpecializationName,
  }) async {
    final source = File(
      _join(specializationDirectory.path, 'My Specialization Notes.md'),
    );

    if (!await source.exists()) {
      return;
    }

    final destinationDirectory = Directory(
      _join(archiveDirectory.path, _safeName(oldSpecializationName)),
    );

    await destinationDirectory.create(recursive: true);

    final desiredPath = _join(
      destinationDirectory.path,
      'My Specialization Notes.md',
    );

    final destination = await _uniqueFilePath(desiredPath);

    await _moveFile(source, File(destination));
  }

  Future<void> _restoreSpecializationNotes({
    required Directory specializationDirectory,
    required Directory archiveDirectory,
    required String specializationName,
  }) async {
    final activeFile = File(
      _join(specializationDirectory.path, 'My Specialization Notes.md'),
    );

    if (await activeFile.exists()) {
      return;
    }

    final archivedFile = File(
      _join(
        _join(archiveDirectory.path, _safeName(specializationName)),
        'My Specialization Notes.md',
      ),
    );

    if (!await archivedFile.exists()) {
      return;
    }

    await specializationDirectory.create(recursive: true);

    await _moveFile(archivedFile, activeFile);
  }

  Future<void> _restoreArchivedSubject({
    required Directory activeSubjectDirectory,
    required Directory archiveDirectory,
    required String specializationName,
    required String subjectCode,
  }) async {
    if (await activeSubjectDirectory.exists()) {
      return;
    }

    final archivedDirectory = Directory(
      _join(
        _join(archiveDirectory.path, _safeName(specializationName)),
        _safeName(subjectCode),
      ),
    );

    if (!await archivedDirectory.exists()) {
      return;
    }

    await _moveDirectory(archivedDirectory, activeSubjectDirectory);
  }

  Future<void> _removeOldGeneratedSpecializationPages({
    required Directory specializationDirectory,
    required String? currentSpecializationName,
  }) async {
    if (!await specializationDirectory.exists()) {
      return;
    }

    final currentFilename = currentSpecializationName != null
        ? '${_safeName(currentSpecializationName)}.md'.toLowerCase()
        : null;

    await for (final entity in specializationDirectory.list(
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      final filename = _basename(entity.path);

      final lower = filename.toLowerCase();

      if (lower == 'my specialization notes.md') {
        continue;
      }

      if (!lower.endsWith('.md')) {
        continue;
      }

      if (currentFilename != null && lower == currentFilename) {
        continue;
      }

      if (await _isGeneratedFile(entity)) {
        await entity.delete();
      }
    }
  }

  Future<bool> _isGeneratedFile(File file) async {
    try {
      if (!await file.exists()) {
        return false;
      }

      final content = await file.readAsString();

      return content.contains('<!-- Generated by FPT Knowledge.');
    } catch (_) {
      return false;
    }
  }

  // ==================================================
  // CURRICULUM MARKDOWN
  // ==================================================

  String _buildCurriculumIndex({
    required String curriculumCode,
    required List<CurriculumSubject> subjects,
    required SpecializationCombo? specialization,
    required String vaultRelativeRoot,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('<!-- Generated by FPT Knowledge. -->');

    buffer.writeln();
    buffer.writeln('# $curriculumCode');
    buffer.writeln();

    buffer.writeln('> Curriculum information synchronized from FPT FLM.');

    buffer.writeln();
    buffer.writeln('## Semesters');
    buffer.writeln();

    final semesters =
        subjects.map((subject) => subject.semester).toSet().toList()..sort();

    for (final semester in semesters) {
      final filename = _semesterFilename(semester);

      final displayName = semester == 0
          ? 'Preparation / Semester 0'
          : 'Semester $semester';

      buffer.writeln(
        '- [[$vaultRelativeRoot/Semesters/$filename|$displayName]]',
      );
    }

    if (specialization != null) {
      final specializationFileName = _safeName(
        specialization.name.isEmpty ? 'Specialization' : specialization.name,
      );

      buffer.writeln();
      buffer.writeln('## My Specialization');
      buffer.writeln();

      buffer.writeln(
        '[[$vaultRelativeRoot/Specialization/$specializationFileName|${specialization.name}]]',
      );

      buffer.writeln();

      buffer.writeln(
        '[[$vaultRelativeRoot/Specialization/My Specialization Notes|My Specialization Notes]]',
      );
    }

    buffer.writeln();
    buffer.writeln('## Subjects');
    buffer.writeln();

    for (final subject in subjects) {
      final code = _safeName(subject.code);

      buffer.writeln(
        '- [[$vaultRelativeRoot/Subjects/$code/Overview|${subject.code}]] — ${subject.name}',
      );
    }

    return buffer.toString();
  }

  String _buildSemesterMarkdown({
    required int semester,
    required List<CurriculumSubject> subjects,
    required SpecializationCombo? specialization,
    required String vaultRelativeRoot,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('<!-- Generated by FPT Knowledge. -->');

    buffer.writeln();

    if (semester == 0) {
      buffer.writeln('# Preparation / Semester 0');
    } else {
      buffer.writeln('# Semester $semester');
    }

    buffer.writeln();

    for (final subject in subjects) {
      final code = _safeName(subject.code);

      final isSpecialization =
          specialization?.subjects.any(
            (comboSubject) =>
                _subjectKey(comboSubject.code) == _subjectKey(subject.code),
          ) ??
          false;

      buffer.write(
        '- [[$vaultRelativeRoot/Subjects/$code/Overview|${subject.code}]]',
      );

      if (subject.name.isNotEmpty) {
        buffer.write(' — ${subject.name}');
      }

      if (isSpecialization) {
        buffer.write(' **(Specialization)**');
      }

      buffer.writeln();
    }

    return buffer.toString();
  }

  String _buildSpecializationMarkdown({
    required SpecializationCombo combo,
    required String vaultRelativeRoot,
  }) {
    final buffer = StringBuffer();

    buffer.writeln(
      '<!-- Generated by FPT Knowledge. '
      'This file may be refreshed during Sync. -->',
    );

    buffer.writeln();
    buffer.writeln('# ${combo.name}');
    buffer.writeln();

    if (combo.note.trim().isNotEmpty) {
      buffer.writeln(combo.note.trim());
      buffer.writeln();
    }

    buffer.writeln('## Learning Path');
    buffer.writeln();

    final subjects = [...combo.subjects]
      ..sort((a, b) => a.semester.compareTo(b.semester));

    for (final subject in subjects) {
      final safeCode = _safeName(subject.code);

      buffer.writeln(
        '- Semester ${subject.semester} → '
        '[[$vaultRelativeRoot/Subjects/$safeCode/Overview|${subject.code}]]'
        ' — ${subject.name}',
      );
    }

    buffer.writeln();
    buffer.writeln('## Personal Notes');
    buffer.writeln();

    buffer.writeln(
      '[[$vaultRelativeRoot/Specialization/My Specialization Notes|Open my specialization notes]]',
    );

    return buffer.toString();
  }

  // ==================================================
  // SUBJECT MARKDOWN
  // ==================================================

  String _buildOverviewMarkdown({
    required CurriculumSubject subject,
    required SyllabusDetailResult? syllabus,
    required String vaultRelativeRoot,
  }) {
    final buffer = StringBuffer();

    buffer.writeln(
      '<!-- Generated by FPT Knowledge. '
      'This file may be refreshed during Sync. -->',
    );

    buffer.writeln();

    buffer.writeln('# ${subject.code} — ${subject.name}');

    buffer.writeln();

    buffer.writeln('- **Semester:** ${subject.semester}');

    final credits = subject.credits > 0 ? subject.credits : syllabus?.credits;

    if (credits != null && credits > 0) {
      buffer.writeln('- **Credits:** $credits');
    }

    final prerequisite = subject.hasPrerequisite
        ? subject.prerequisite
        : syllabus?.prerequisite ?? '';

    if (prerequisite.trim().isNotEmpty) {
      buffer.writeln('- **Prerequisite:** ${prerequisite.trim()}');
    }

    if (syllabus?.minimumPassMark != null) {
      buffer.writeln(
        '- **Minimum pass mark:** '
        '${syllabus!.minimumPassMark}',
      );
    }

    buffer.writeln();

    final safeCode = _safeName(subject.code);

    buffer.writeln('## Related Notes');
    buffer.writeln();

    buffer.writeln(
      '- [[$vaultRelativeRoot/Subjects/$safeCode/Assessment|Assessment]]',
    );

    buffer.writeln(
      '- [[$vaultRelativeRoot/Subjects/$safeCode/Materials|Materials]]',
    );

    buffer.writeln(
      '- [[$vaultRelativeRoot/Subjects/$safeCode/My Notes|My Notes]]',
    );

    buffer.writeln();

    if (syllabus == null) {
      buffer.writeln('## FLM Syllabus');
      buffer.writeln();

      buffer.writeln(
        'No detailed syllabus information was available from FLM during this sync.',
      );

      return buffer.toString();
    }

    if (syllabus.description.trim().isNotEmpty) {
      buffer.writeln('## About this subject');
      buffer.writeln();

      buffer.writeln(syllabus.description.trim());
      buffer.writeln();
    }

    if (syllabus.timeAllocation.trim().isNotEmpty) {
      buffer.writeln('## Study Time');
      buffer.writeln();

      buffer.writeln(syllabus.timeAllocation.trim());
      buffer.writeln();
    }

    if (syllabus.teachingMethod.trim().isNotEmpty) {
      buffer.writeln('## Teaching Method');
      buffer.writeln();

      buffer.writeln(syllabus.teachingMethod.trim());
      buffer.writeln();
    }

    if (syllabus.tools.trim().isNotEmpty ||
        syllabus.studentTasks.trim().isNotEmpty) {
      buffer.writeln('## What You Need');
      buffer.writeln();

      if (syllabus.tools.trim().isNotEmpty) {
        buffer.writeln('### Tools');
        buffer.writeln();

        buffer.writeln(syllabus.tools.trim());
        buffer.writeln();
      }

      if (syllabus.studentTasks.trim().isNotEmpty) {
        buffer.writeln('### Student Requirements');
        buffer.writeln();

        buffer.writeln(syllabus.studentTasks.trim());
        buffer.writeln();
      }
    }

    if (syllabus.outcomes.isNotEmpty) {
      buffer.writeln('## What You Will Learn');
      buffer.writeln();

      for (final outcome in syllabus.outcomes) {
        final name = outcome.name.trim();

        final details = outcome.details.trim();

        if (name.isNotEmpty && details.isNotEmpty) {
          buffer.writeln('- **$name:** $details');
        } else if (details.isNotEmpty) {
          buffer.writeln('- $details');
        }
      }

      buffer.writeln();
    }

    if (syllabus.url.trim().isNotEmpty) {
      buffer.writeln('## FLM Source');
      buffer.writeln();

      buffer.writeln(syllabus.url.trim());
    }

    return buffer.toString();
  }

  String _buildAssessmentMarkdown({
    required CurriculumSubject subject,
    required SyllabusDetailResult? syllabus,
  }) {
    final buffer = StringBuffer();

    buffer.writeln(
      '<!-- Generated by FPT Knowledge. '
      'This file may be refreshed during Sync. -->',
    );

    buffer.writeln();
    buffer.writeln('# ${subject.code} — Assessment');
    buffer.writeln();

    if (syllabus == null || syllabus.assessments.isEmpty) {
      buffer.writeln('No assessment information was retrieved from FLM.');

      return buffer.toString();
    }

    for (final assessment in syllabus.assessments) {
      final title = assessment.category.trim().isNotEmpty
          ? assessment.category.trim()
          : 'Assessment';

      buffer.writeln('## $title');
      buffer.writeln();

      _writeField(buffer, 'Type', assessment.type);

      _writeField(buffer, 'Part', assessment.part);

      _writeField(buffer, 'Weight', assessment.weight);

      _writeField(buffer, 'Completion Criteria', assessment.completionCriteria);

      _writeField(buffer, 'Duration', assessment.duration);

      _writeField(buffer, 'CLO', assessment.clo);

      _writeField(buffer, 'Question Type', assessment.questionType);

      _writeField(buffer, 'Number of Questions', assessment.numberOfQuestions);

      if (assessment.knowledgeAndSkill.trim().isNotEmpty) {
        buffer.writeln();

        buffer.writeln('### Knowledge & Skill');
        buffer.writeln();

        buffer.writeln(assessment.knowledgeAndSkill.trim());
      }

      if (assessment.gradingGuide.trim().isNotEmpty) {
        buffer.writeln();

        buffer.writeln('### Grading Guide');
        buffer.writeln();

        buffer.writeln(assessment.gradingGuide.trim());
      }

      if (assessment.note.trim().isNotEmpty) {
        buffer.writeln();

        buffer.writeln('### Note');
        buffer.writeln();

        buffer.writeln(assessment.note.trim());
      }

      buffer.writeln();
    }

    return buffer.toString();
  }

  String _buildMaterialsMarkdown({
    required CurriculumSubject subject,
    required SyllabusDetailResult? syllabus,
  }) {
    final buffer = StringBuffer();

    buffer.writeln(
      '<!-- Generated by FPT Knowledge. '
      'This file may be refreshed during Sync. -->',
    );

    buffer.writeln();
    buffer.writeln('# ${subject.code} — Materials');
    buffer.writeln();

    if (syllabus == null || syllabus.materials.isEmpty) {
      buffer.writeln('No learning materials were retrieved from FLM.');

      return buffer.toString();
    }

    for (final material in syllabus.materials) {
      final title = material.description.trim().isNotEmpty
          ? material.description.trim()
          : 'Learning Material';

      buffer.writeln('## $title');
      buffer.writeln();

      _writeField(buffer, 'Author', material.author);

      _writeField(buffer, 'Publisher', material.publisher);

      _writeField(buffer, 'Published Date', material.publishedDate);

      _writeField(buffer, 'Edition', material.edition);

      _writeField(buffer, 'ISBN', material.isbn);

      buffer.writeln(
        '- **Main material:** '
        '${material.isMain ? 'Yes' : 'No'}',
      );

      buffer.writeln(
        '- **Online:** '
        '${material.isOnline ? 'Yes' : 'No'}',
      );

      if (material.note.trim().isNotEmpty) {
        buffer.writeln();

        buffer.writeln(material.note.trim());
      }

      buffer.writeln();
    }

    return buffer.toString();
  }

  String _buildMyNotesMarkdown(CurriculumSubject subject) {
    return '''
# ${subject.code} — My Notes

> This file belongs to you.
> FPT Knowledge will never overwrite it.

## Class Notes


## Important Concepts


## Questions


## Assignment / Project Notes


## Exam Preparation


''';
  }

  // ==================================================
  // FILE HELPERS
  // ==================================================

  Future<void> _moveDirectory(Directory source, Directory destination) async {
    await destination.parent.create(recursive: true);

    try {
      await source.rename(destination.path);

      return;
    } catch (_) {}

    await _copyDirectory(source, destination);

    await source.delete(recursive: true);
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);

    await for (final entity in source.list(followLinks: false)) {
      final name = _basename(entity.path);

      final targetPath = _join(destination.path, name);

      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  Future<void> _moveFile(File source, File destination) async {
    await destination.parent.create(recursive: true);

    try {
      await source.rename(destination.path);

      return;
    } catch (_) {}

    await source.copy(destination.path);

    await source.delete();
  }

  Future<String> _uniqueDirectoryPath(String desiredPath) async {
    if (!await Directory(desiredPath).exists()) {
      return desiredPath;
    }

    final suffix = DateTime.now().millisecondsSinceEpoch;

    return '$desiredPath - $suffix';
  }

  Future<String> _uniqueFilePath(String desiredPath) async {
    if (!await File(desiredPath).exists()) {
      return desiredPath;
    }

    final dot = desiredPath.lastIndexOf('.');

    final suffix = DateTime.now().millisecondsSinceEpoch;

    if (dot <= 0) {
      return '$desiredPath - $suffix';
    }

    final base = desiredPath.substring(0, dot);

    final extension = desiredPath.substring(dot);

    return '$base - $suffix$extension';
  }

  void _writeField(StringBuffer buffer, String label, String value) {
    if (value.trim().isEmpty) {
      return;
    }

    buffer.writeln('- **$label:** ${value.trim()}');
  }

  Future<void> _writeGeneratedFile(File file, String content) async {
    await file.parent.create(recursive: true);

    await file.writeAsString(content, flush: true);
  }

  String _subjectKey(String code) {
    return _safeName(code.trim().toUpperCase()).toUpperCase();
  }

  String _semesterFilename(int semester) {
    return 'Semester '
        '${semester.toString().padLeft(2, '0')}';
  }

  String _safeName(String value) {
    var result = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();

    result = result.replaceAll(RegExp(r'[. ]+$'), '');

    if (result.isEmpty) {
      return 'Untitled';
    }

    return result;
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');

    final pieces = normalized.split('/');

    return pieces.isEmpty ? path : pieces.last;
  }

  String _withoutMd(String filename) {
    if (filename.toLowerCase().endsWith('.md')) {
      return filename.substring(0, filename.length - 3);
    }

    return filename;
  }

  String _join(String first, String second) {
    return '$first'
        '${Platform.pathSeparator}'
        '$second';
  }
}
