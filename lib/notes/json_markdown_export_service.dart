import 'dart:convert';
import 'dart:io';

import '../database/database_repository.dart';
import '../flm/flm_combo_service.dart';
import '../obsidian/obsidian_service.dart';
import '../settings/app_settings.dart';

class MarkdownExportResult {
  final String path;
  final int exportedSubjects;
  final bool created;

  const MarkdownExportResult({
    required this.path,
    required this.exportedSubjects,
    this.created = true,
  });
}

enum MyNotesItemType { subject, curriculum }

class MyNotesLibraryItem {
  final MyNotesItemType type;
  final String code;
  final String title;
  final String relativePath;

  const MyNotesLibraryItem({
    required this.type,
    required this.code,
    required this.title,
    required this.relativePath,
  });

  String get id => '${type.name}:$code';

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'code': code,
    'title': title,
    'relativePath': relativePath,
  };

  factory MyNotesLibraryItem.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString() == 'curriculum'
        ? MyNotesItemType.curriculum
        : MyNotesItemType.subject;
    return MyNotesLibraryItem(
      type: type,
      code: json['code']?.toString().trim().toUpperCase() ?? '',
      title: json['title']?.toString().trim() ?? '',
      relativePath: json['relativePath']?.toString().trim() ?? '',
    );
  }
}

class JsonMarkdownExportService {
  final DatabaseRepository repository;
  final ObsidianService obsidianService;
  final AppSettings settings;

  JsonMarkdownExportService(
    this.repository, {
    ObsidianService? obsidianService,
    AppSettings? settings,
  }) : obsidianService = obsidianService ?? ObsidianService(),
       settings = settings ?? AppSettings.instance;

  Future<MarkdownExportResult?> addSubjectToMyNotes(
    String subjectCode, {
    Directory? rootDirectory,
  }) async {
    final root = await _root(rootDirectory);
    if (root == null) return null;
    final code = subjectCode.trim().toUpperCase();
    final subject = await repository.loadSubject(code);
    if (subject == null) {
      throw StateError('Subject $code is unavailable locally.');
    }
    final title = _subjectTitle(subject, code);
    final relativePath = 'Subjects/${_safe(code)}.md';
    final item = MyNotesLibraryItem(
      type: MyNotesItemType.subject,
      code: code,
      title: title,
      relativePath: relativePath,
    );
    final file = await _personalNoteFile(root, item);
    final existed = await file.exists();
    if (!existed) {
      await file.writeAsString(
        _subjectCombinedMarkdown(code, title, subject),
        flush: true,
      );
    }
    await _registerItem(root, item);
    return MarkdownExportResult(
      path: file.path,
      exportedSubjects: 1,
      created: !existed,
    );
  }

  Future<MarkdownExportResult?> addCurriculumToMyNotes(
    String curriculumCode, {
    Directory? rootDirectory,
  }) async {
    final root = await _root(rootDirectory);
    if (root == null) return null;
    final curriculum = await repository.loadCurriculum(curriculumCode);
    if (curriculum == null) {
      throw StateError('Curriculum $curriculumCode is unavailable locally.');
    }
    final selected = await settings.getSpecialization(curriculum.code);
    final specializations = await repository.loadSpecializations(
      curriculum.code,
    );
    final coreSubjects = curriculum.subjects
        .where((subject) => !subject.isComboPlaceholder)
        .toList();
    final activeSubjects = _uniqueSubjects([
      ...coreSubjects,
      if (selected != null) ..._comboSubjects(selected),
    ]);
    final packageSubjects = _uniqueSubjects([
      ...coreSubjects,
      for (final specialization in specializations)
        ..._comboSubjects(specialization),
      if (selected != null) ..._comboSubjects(selected),
    ]);
    final relativePath = 'Curricula/${_safe(curriculum.code)}/Curriculum.md';
    final item = MyNotesLibraryItem(
      type: MyNotesItemType.curriculum,
      code: curriculum.code,
      title: curriculum.name.isEmpty ? curriculum.code : curriculum.name,
      relativePath: relativePath,
    );
    final file = await _personalNoteFile(root, item);
    final packageRoot = file.parent;
    await _writeGenerated(
      file,
      _linkedCurriculumMarkdown(
        curriculum,
        activeSubjects,
        hasSpecializations: specializations.isNotEmpty || selected != null,
      ),
    );
    final semesters =
        activeSubjects.map((subject) => subject.semester).toSet().toList()
          ..sort();
    for (final semester in semesters) {
      await _writeLinkedSemester(
        packageRoot,
        semester,
        activeSubjects
            .where((subject) => subject.semester == semester)
            .toList(),
      );
    }
    var exported = 0;
    for (final subject in packageSubjects) {
      final json = await repository.loadSubject(subject.code);
      if (json == null) continue;
      await _writeSubject(
        curriculumRoot: packageRoot,
        curriculumCode: curriculum.code,
        code: subject.code,
        subject: json,
        semester: subject.semester,
        curriculumName: subject.name,
        curriculumCredits: subject.credits,
        curriculumPrerequisite: subject.prerequisite,
        relativeLinks: true,
      );
      exported++;
    }
    if (specializations.isNotEmpty || selected != null) {
      await _writeLinkedSpecializations(packageRoot, specializations, selected);
    }
    await _writeGenerated(
      File(_join(packageRoot.path, '.fpt_knowledge_export.json')),
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'source': 'read-only-local-json-database',
        'curriculumCode': curriculum.code,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    await _registerItem(root, item);
    return MarkdownExportResult(path: file.path, exportedSubjects: exported);
  }

  Future<List<MyNotesLibraryItem>> listMyNotes(Directory rootDirectory) async {
    final manifest = File(
      _join((await _libraryRoot(rootDirectory)).path, '.library.json'),
    );
    if (!await manifest.exists()) return const [];
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      final rawItems = decoded is Map ? decoded['items'] : null;
      if (rawItems is! List) return const [];
      final items = rawItems
          .whereType<Map>()
          .map(
            (raw) =>
                MyNotesLibraryItem.fromJson(Map<String, dynamic>.from(raw)),
          )
          .where(
            (item) =>
                item.code.isNotEmpty &&
                item.relativePath.isNotEmpty &&
                !item.relativePath.split('/').contains('..'),
          )
          .toList();
      items.sort((a, b) {
        final type = a.type.index.compareTo(b.type.index);
        return type != 0 ? type : a.code.compareTo(b.code);
      });
      return items;
    } catch (_) {
      throw const FormatException('My Notes library registry is unreadable.');
    }
  }

  Future<File> myNotesFile(
    Directory rootDirectory,
    MyNotesLibraryItem item,
  ) async {
    return _personalNoteFile(rootDirectory, item);
  }

  Future<void> removeFromMyNotes(
    Directory rootDirectory,
    MyNotesLibraryItem item,
  ) async {
    final items = await listMyNotes(rootDirectory);
    final registered = items.any(
      (candidate) =>
          candidate.id == item.id &&
          candidate.relativePath == item.relativePath,
    );
    if (!registered) return;
    final file = await _personalNoteFile(rootDirectory, item);
    if (item.type == MyNotesItemType.curriculum) {
      if (await file.parent.exists()) {
        await file.parent.delete(recursive: true);
      }
    } else if (await file.exists()) {
      await file.delete();
    }
    await _writeRegistry(
      rootDirectory,
      items.where((candidate) => candidate.id != item.id).toList(),
    );
  }

  List<DatabaseCurriculumSubject> _comboSubjects(
    SpecializationCombo specialization,
  ) => [
    for (final item in specialization.subjects)
      DatabaseCurriculumSubject(
        code: item.code,
        name: item.name,
        semester: item.semester,
        credits: 0,
        prerequisite: '',
        isComboPlaceholder: false,
      ),
  ];

  List<DatabaseCurriculumSubject> _uniqueSubjects(
    Iterable<DatabaseCurriculumSubject> subjects,
  ) {
    final values = <String, DatabaseCurriculumSubject>{};
    for (final subject in subjects) {
      final code = subject.code.trim().toUpperCase();
      if (code.isNotEmpty) values.putIfAbsent(code, () => subject);
    }
    final result = values.values.toList()
      ..sort((a, b) {
        final semester = a.semester.compareTo(b.semester);
        return semester != 0 ? semester : a.code.compareTo(b.code);
      });
    return result;
  }

  String _linkedCurriculumMarkdown(
    DatabaseCurriculum curriculum,
    List<DatabaseCurriculumSubject> subjects, {
    required bool hasSpecializations,
  }) {
    final buffer = StringBuffer(_header)
      ..writeln('# ${curriculum.code}')
      ..writeln();
    if (curriculum.name.isNotEmpty) buffer.writeln('**${curriculum.name}**\n');
    if (curriculum.totalCredits != null) {
      buffer.writeln('- **Total credits:** ${curriculum.totalCredits}');
    }
    final semesters = subjects.map((item) => item.semester).toSet().toList()
      ..sort();
    for (final semester in semesters) {
      final label = semester == 0 ? 'Preparation' : 'Semester $semester';
      buffer
        ..writeln('\n## $label\n')
        ..writeln(
          '[[Semesters/${_semesterFilename(semester)}|Open $label note]]\n',
        );
      for (final item in subjects.where((item) => item.semester == semester)) {
        buffer.writeln(
          '- [[Subjects/${_safe(item.code)}/Overview|${item.code}'
          '${item.name.isEmpty ? '' : ' — ${item.name}'}]]',
        );
      }
    }
    if (hasSpecializations) {
      buffer.writeln(
        '\n## Specializations\n\n[[Specialization/Index|Browse specializations]]',
      );
    }
    return buffer.toString();
  }

  Future<void> _writeLinkedSemester(
    Directory packageRoot,
    int semester,
    List<DatabaseCurriculumSubject> subjects,
  ) async {
    final buffer = StringBuffer(_header)
      ..writeln(semester == 0 ? '# Preparation' : '# Semester $semester')
      ..writeln();
    for (final item in subjects) {
      buffer.writeln(
        '- [[../Subjects/${_safe(item.code)}/Overview|${item.code}'
        '${item.name.isEmpty ? '' : ' — ${item.name}'}]]',
      );
    }
    await _writeGenerated(
      File(
        _join(
          packageRoot.path,
          'Semesters',
          '${_semesterFilename(semester)}.md',
        ),
      ),
      buffer.toString(),
    );
  }

  Future<void> _writeLinkedSpecializations(
    Directory packageRoot,
    List<SpecializationCombo> choices,
    SpecializationCombo? selected,
  ) async {
    final directory = Directory(_join(packageRoot.path, 'Specialization'));
    await directory.create(recursive: true);
    final all = <String, SpecializationCombo>{
      for (final choice in choices) choice.name: choice,
    };
    if (selected != null) all[selected.name] = selected;
    final index = StringBuffer(_header)..writeln('# Specializations\n');
    for (final choice in all.values) {
      index.writeln(
        '- [[${_safe(choice.name)}|${choice.name}]]'
        '${selected?.name == choice.name ? ' — Selected' : ''}',
      );
      final page = StringBuffer(_header)
        ..writeln('# ${choice.name}')
        ..writeln();
      if (choice.note.isNotEmpty) page.writeln('${choice.note}\n');
      for (final subject in choice.subjects) {
        page.writeln(
          '- Semester ${subject.semester} → '
          '[[../Subjects/${_safe(subject.code)}/Overview|${subject.code} — ${subject.name}]]',
        );
      }
      await _writeGenerated(
        File(_join(directory.path, '${_safe(choice.name)}.md')),
        page.toString(),
      );
    }
    await _writeGenerated(
      File(_join(directory.path, 'Index.md')),
      index.toString(),
    );
    final notes = File(_join(directory.path, 'My Specialization Notes.md'));
    if (!await notes.exists()) {
      await notes.writeAsString(
        '# My Specialization Notes\n\n'
        '> This file belongs to you.\n'
        '> FPT Knowledge will never overwrite it.\n\n',
        flush: true,
      );
    }
  }

  Future<MarkdownExportResult?> exportSubject(
    String subjectCode, {
    String? curriculumCode,
    Directory? rootDirectory,
  }) async {
    final root = await _root(rootDirectory);
    if (root == null) return null;
    final code = subjectCode.trim().toUpperCase();
    final subject = await repository.loadSubject(code);
    if (subject == null) {
      throw StateError('Subject $code is unavailable locally.');
    }
    final curriculum = curriculumCode?.trim().isNotEmpty == true
        ? curriculumCode!.trim().toUpperCase()
        : (await settings.getCurrentCurriculum()) ?? 'General';
    final curriculumRoot = await _curriculumRoot(root, curriculum);
    await _writeSubject(
      curriculumRoot: curriculumRoot,
      curriculumCode: curriculum,
      code: code,
      subject: subject,
    );
    return MarkdownExportResult(
      path: _join(curriculumRoot.path, 'Subjects', _safe(code)),
      exportedSubjects: 1,
    );
  }

  Future<MarkdownExportResult?> exportSemester(
    String curriculumCode,
    int semester, {
    Directory? rootDirectory,
  }) async {
    final root = await _root(rootDirectory);
    if (root == null) return null;
    final curriculum = await repository.loadCurriculum(curriculumCode);
    if (curriculum == null) {
      throw StateError('Curriculum $curriculumCode is unavailable locally.');
    }
    final curriculumRoot = await _curriculumRoot(root, curriculum.code);
    final subjects = curriculum.subjects
        .where((item) => item.semester == semester && !item.isComboPlaceholder)
        .toList();
    await _writeSemester(curriculumRoot, curriculum.code, semester, subjects);
    var exported = 0;
    for (final item in subjects) {
      final json = await repository.loadSubject(item.code);
      if (json == null) continue;
      await _writeSubject(
        curriculumRoot: curriculumRoot,
        curriculumCode: curriculum.code,
        code: item.code,
        subject: json,
        semester: semester,
        curriculumName: item.name,
        curriculumCredits: item.credits,
        curriculumPrerequisite: item.prerequisite,
      );
      exported++;
    }
    return MarkdownExportResult(
      path: _join(
        curriculumRoot.path,
        'Semesters',
        '${_semesterFilename(semester)}.md',
      ),
      exportedSubjects: exported,
    );
  }

  Future<MarkdownExportResult?> exportCurriculum(
    String curriculumCode, {
    Directory? rootDirectory,
  }) async {
    final root = await _root(rootDirectory);
    if (root == null) return null;
    final curriculum = await repository.loadCurriculum(curriculumCode);
    if (curriculum == null) {
      throw StateError('Curriculum $curriculumCode is unavailable locally.');
    }
    final curriculumRoot = await _curriculumRoot(root, curriculum.code);
    final selected = await settings.getSpecialization(curriculum.code);
    final active = <DatabaseCurriculumSubject>[
      ...curriculum.subjects.where((item) => !item.isComboPlaceholder),
      ...?selected?.subjects.map(
        (item) => DatabaseCurriculumSubject(
          code: item.code,
          name: item.name,
          semester: item.semester,
          credits: 0,
          prerequisite: '',
          isComboPlaceholder: false,
        ),
      ),
    ];
    active.sort((a, b) {
      final semester = a.semester.compareTo(b.semester);
      return semester != 0 ? semester : a.code.compareTo(b.code);
    });

    await _writeGenerated(
      File(_join(curriculumRoot.path, 'Curriculum.md')),
      _curriculumMarkdown(curriculum, active, selected),
    );
    final semesters = active.map((item) => item.semester).toSet().toList()
      ..sort();
    for (final semester in semesters) {
      await _writeSemester(
        curriculumRoot,
        curriculum.code,
        semester,
        active.where((item) => item.semester == semester).toList(),
      );
    }
    if (selected != null) {
      await _writeSpecialization(curriculumRoot, curriculum.code, selected);
    }
    var exported = 0;
    for (final item in active) {
      final json = await repository.loadSubject(item.code);
      if (json == null) continue;
      await _writeSubject(
        curriculumRoot: curriculumRoot,
        curriculumCode: curriculum.code,
        code: item.code,
        subject: json,
        semester: item.semester,
        curriculumName: item.name,
        curriculumCredits: item.credits,
        curriculumPrerequisite: item.prerequisite,
      );
      exported++;
    }
    await _writeGenerated(
      File(_join(curriculumRoot.path, '.fpt_knowledge_sync.json')),
      const JsonEncoder.withIndent('  ').convert({
        'version': 2,
        'source': 'bundled-json-database',
        'specializationName': selected?.name,
        'specializationSubjectCodes': [
          ...?selected?.subjects.map((item) => item.code),
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    return MarkdownExportResult(
      path: curriculumRoot.path,
      exportedSubjects: exported,
    );
  }

  Future<Directory?> _root(Directory? supplied) async {
    if (supplied != null) {
      await supplied.create(recursive: true);
      return supplied;
    }
    final saved = await obsidianService.getSavedVaultPath();
    final selected = saved ?? await obsidianService.chooseVault();
    return selected == null ? null : Directory(selected);
  }

  Future<Directory> _curriculumRoot(Directory root, String curriculum) async {
    final directory = Directory(
      _join(root.path, 'FPT Knowledge', _safe(curriculum)),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _libraryRoot(Directory root) async {
    if (!await root.exists()) {
      throw StateError('The selected knowledge folder no longer exists.');
    }
    final directory = Directory(
      _join(_join(root.path, 'FPT Knowledge'), 'My Notes'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _personalNoteFile(
    Directory root,
    MyNotesLibraryItem item,
  ) async {
    if (item.relativePath.split('/').contains('..')) {
      throw StateError('Invalid My Notes path.');
    }
    final library = await _libraryRoot(root);
    final platformRelative = item.relativePath.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    final file = File(_join(library.path, platformRelative));
    await file.parent.create(recursive: true);
    return file;
  }

  Future<void> _registerItem(Directory root, MyNotesLibraryItem item) async {
    final items = await listMyNotes(root);
    final updated = [
      item,
      ...items.where((existing) => existing.id != item.id),
    ];
    await _writeRegistry(root, updated);
  }

  Future<void> _writeRegistry(
    Directory root,
    List<MyNotesLibraryItem> items,
  ) async {
    final library = await _libraryRoot(root);
    final file = File(_join(library.path, '.library.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'items': items.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );
  }

  String _subjectCombinedMarkdown(
    String code,
    String title,
    Map<String, dynamic> json,
  ) {
    final buffer = StringBuffer(_personalHeader)
      ..writeln('# $code — $title')
      ..writeln();
    for (final entry in <String, Object?>{
      'Credits': json['credits'],
      'Prerequisite': json['prerequisite'],
      'Minimum pass mark': json['minimumPassMark'],
    }.entries) {
      final value = _text(entry.value);
      if (value.isNotEmpty) buffer.writeln('- **${entry.key}:** $value');
    }
    for (final entry in <String, Object?>{
      'Description': json['description'],
      'Teaching method': json['teachingMethod'],
      'Time allocation': json['timeAllocation'],
      'Student tasks': json['studentTasks'],
      'Tools': json['tools'],
    }.entries) {
      final value = _text(entry.value);
      if (value.isNotEmpty) buffer.writeln('\n## ${entry.key}\n\n$value');
    }
    final outcomes = _maps(json['learningOutcomes']);
    if (outcomes.isNotEmpty) {
      buffer.writeln('\n## Learning outcomes\n');
      for (final item in outcomes) {
        buffer.writeln(
          '- **${_text(item['name'])}:** ${_text(item['details'])}',
        );
      }
    }
    final assessments = _maps(json['assessments']);
    if (assessments.isNotEmpty) {
      buffer.writeln('\n## Assessment\n');
      for (final item in assessments) {
        buffer.writeln(
          '- **${_text(item['category'])}** — ${_text(item['weight'])}'
          '${_text(item['type']).isEmpty ? '' : ' (${_text(item['type'])})'}',
        );
      }
    }
    final materials = _maps(json['learningMaterials']);
    if (materials.isNotEmpty) {
      buffer.writeln('\n## Learning materials\n');
      for (final item in materials) {
        buffer.writeln(
          '- ${_text(item['description'])}'
          '${_text(item['author']).isEmpty ? '' : ' — ${_text(item['author'])}'}',
        );
      }
    }
    buffer.writeln('\n## My notes\n');
    return buffer.toString();
  }

  static String _subjectTitle(Map<String, dynamic> subject, String fallback) {
    final syllabusName = _text(subject['syllabusName']);
    if (syllabusName.isNotEmpty) return syllabusName;
    final englishName = _text(subject['englishName']);
    return englishName.isEmpty ? fallback : englishName;
  }

  Future<void> _writeSubject({
    required Directory curriculumRoot,
    required String curriculumCode,
    required String code,
    required Map<String, dynamic> subject,
    int? semester,
    String? curriculumName,
    int? curriculumCredits,
    String? curriculumPrerequisite,
    bool relativeLinks = false,
  }) async {
    final directory = Directory(
      _join(curriculumRoot.path, 'Subjects', _safe(code)),
    );
    await directory.create(recursive: true);
    await _writeGenerated(
      File(_join(directory.path, 'Overview.md')),
      _overviewMarkdown(
        curriculumCode,
        code,
        subject,
        semester: semester,
        curriculumName: curriculumName,
        curriculumCredits: curriculumCredits,
        curriculumPrerequisite: curriculumPrerequisite,
        relativeLinks: relativeLinks,
      ),
    );
    await _writeGenerated(
      File(_join(directory.path, 'Assessment.md')),
      _assessmentMarkdown(code, subject),
    );
    await _writeGenerated(
      File(_join(directory.path, 'Materials.md')),
      _materialsMarkdown(code, subject),
    );
    final notes = File(_join(directory.path, 'My Notes.md'));
    if (!await notes.exists()) {
      await notes.writeAsString(
        '# $code — My Notes\n\n'
        '> This file belongs to you.\n'
        '> FPT Knowledge will never overwrite it.\n\n'
        '## Class Notes\n\n\n## Important Concepts\n\n\n'
        '## Questions\n\n\n## Exam Preparation\n\n',
        flush: true,
      );
    }
  }

  Future<void> _writeSemester(
    Directory root,
    String curriculum,
    int semester,
    List<DatabaseCurriculumSubject> subjects,
  ) async {
    final buffer = StringBuffer(_header);
    buffer.writeln(
      semester == 0 ? '# Preparation / Semester 0' : '# Semester $semester',
    );
    buffer.writeln();
    for (final item in subjects) {
      buffer.writeln(
        '- [[$curriculum/Subjects/${_safe(item.code)}/Overview|${item.code}]]'
        '${item.name.isEmpty ? '' : ' — ${item.name}'}',
      );
    }
    await _writeGenerated(
      File(_join(root.path, 'Semesters', '${_semesterFilename(semester)}.md')),
      buffer.toString(),
    );
  }

  Future<void> _writeSpecialization(
    Directory root,
    String curriculum,
    SpecializationCombo selected,
  ) async {
    final directory = Directory(_join(root.path, 'Specialization'));
    await directory.create(recursive: true);
    final buffer = StringBuffer(_header)
      ..writeln('# ${selected.name}')
      ..writeln();
    if (selected.note.isNotEmpty) buffer.writeln('${selected.note}\n');
    for (final item in selected.subjects) {
      buffer.writeln(
        '- Semester ${item.semester} → '
        '[[$curriculum/Subjects/${_safe(item.code)}/Overview|${item.code}]] — ${item.name}',
      );
    }
    await _writeGenerated(
      File(_join(directory.path, '${_safe(selected.name)}.md')),
      buffer.toString(),
    );
    final notes = File(_join(directory.path, 'My Specialization Notes.md'));
    if (!await notes.exists()) {
      await notes.writeAsString(
        '# My Specialization Notes\n\n'
        '> This file belongs to you.\n'
        '> FPT Knowledge will never overwrite it.\n\n',
        flush: true,
      );
    }
  }

  String _curriculumMarkdown(
    DatabaseCurriculum curriculum,
    List<DatabaseCurriculumSubject> subjects,
    SpecializationCombo? specialization,
  ) {
    final buffer = StringBuffer(_header)
      ..writeln('# ${curriculum.code}')
      ..writeln()
      ..writeln(
        '> Curriculum information generated from the local FPT Knowledge database.',
      )
      ..writeln()
      ..writeln('## Semesters')
      ..writeln();
    final semesters = subjects.map((item) => item.semester).toSet().toList()
      ..sort();
    for (final semester in semesters) {
      buffer.writeln(
        '- [[${curriculum.code}/Semesters/${_semesterFilename(semester)}|'
        '${semester == 0 ? 'Preparation / Semester 0' : 'Semester $semester'}]]',
      );
    }
    if (specialization != null) {
      buffer
        ..writeln()
        ..writeln('## My Specialization')
        ..writeln()
        ..writeln(
          '[[${curriculum.code}/Specialization/${_safe(specialization.name)}|${specialization.name}]]',
        );
    }
    buffer
      ..writeln()
      ..writeln('## Subjects')
      ..writeln();
    for (final item in subjects) {
      buffer.writeln(
        '- [[${curriculum.code}/Subjects/${_safe(item.code)}/Overview|${item.code}]]'
        '${item.name.isEmpty ? '' : ' — ${item.name}'}',
      );
    }
    return buffer.toString();
  }

  String _overviewMarkdown(
    String curriculum,
    String code,
    Map<String, dynamic> json, {
    int? semester,
    String? curriculumName,
    int? curriculumCredits,
    String? curriculumPrerequisite,
    bool relativeLinks = false,
  }) {
    final name = _text(json['syllabusName']).isNotEmpty
        ? _text(json['syllabusName'])
        : (curriculumName ?? _text(json['englishName']));
    final credits = json['credits'] ?? curriculumCredits;
    final prerequisite = _text(json['prerequisite']).isNotEmpty
        ? _text(json['prerequisite'])
        : (curriculumPrerequisite ?? '');
    final buffer = StringBuffer(_header)
      ..writeln('# $code — $name')
      ..writeln();
    if (semester != null) buffer.writeln('- **Semester:** $semester');
    if (credits != null) buffer.writeln('- **Credits:** $credits');
    if (prerequisite.isNotEmpty) {
      buffer.writeln('- **Prerequisite:** $prerequisite');
    }
    if (json['minimumPassMark'] != null) {
      buffer.writeln('- **Minimum pass mark:** ${json['minimumPassMark']}');
    }
    buffer
      ..writeln()
      ..writeln('## Related Notes')
      ..writeln();
    if (relativeLinks) {
      buffer
        ..writeln('- [[Assessment|Assessment]]')
        ..writeln('- [[Materials|Materials]]')
        ..writeln('- [[My Notes|My Notes]]');
    } else {
      buffer
        ..writeln(
          '- [[$curriculum/Subjects/${_safe(code)}/Assessment|Assessment]]',
        )
        ..writeln(
          '- [[$curriculum/Subjects/${_safe(code)}/Materials|Materials]]',
        )
        ..writeln(
          '- [[$curriculum/Subjects/${_safe(code)}/My Notes|My Notes]]',
        );
    }
    for (final entry in <String, Object?>{
      'About this subject': json['description'],
      'Teaching Method': json['teachingMethod'],
      'Study Time': json['timeAllocation'],
      'Student Tasks': json['studentTasks'],
      'Tools': json['tools'],
    }.entries) {
      final value = _text(entry.value);
      if (value.isNotEmpty) buffer.writeln('\n## ${entry.key}\n\n$value');
    }
    final outcomes = _maps(json['learningOutcomes']);
    if (outcomes.isNotEmpty) {
      buffer.writeln('\n## Learning Outcomes\n');
      for (final item in outcomes) {
        buffer.writeln(
          '- **${_text(item['name'])}:** ${_text(item['details'])}',
        );
      }
    }
    return buffer.toString();
  }

  String _assessmentMarkdown(String code, Map<String, dynamic> json) {
    final buffer = StringBuffer(_header)..writeln('# $code — Assessment\n');
    final values = _maps(json['assessments']);
    if (values.isEmpty) return '${buffer}No assessment data is available.\n';
    for (final item in values) {
      buffer.writeln(
        '## ${_text(item['category'])} — ${_text(item['weight'])}\n',
      );
      for (final entry in <String, Object?>{
        'Type': item['type'],
        'Duration': item['duration'],
        'Completion criteria': item['completionCriteria'],
        'CLO': item['clo'],
        'Question type': item['questionType'],
        'Questions': item['numberOfQuestions'],
        'Knowledge and skills': item['knowledgeAndSkill'],
        'Grading guide': item['gradingGuide'],
        'Note': item['note'],
      }.entries) {
        final value = _text(entry.value);
        if (value.isNotEmpty) buffer.writeln('- **${entry.key}:** $value');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _materialsMarkdown(String code, Map<String, dynamic> json) {
    final buffer = StringBuffer(_header)..writeln('# $code — Materials\n');
    final values = _maps(json['learningMaterials']);
    if (values.isEmpty) {
      return '${buffer}No learning material data is available.\n';
    }
    for (final item in values) {
      buffer.writeln('## ${_text(item['description'])}\n');
      for (final entry in <String, Object?>{
        'Author': item['author'],
        'Publisher': item['publisher'],
        'Published date': item['publishedDate'],
        'Edition': item['edition'],
        'ISBN': item['isbn'],
      }.entries) {
        final value = _text(entry.value);
        if (value.isNotEmpty) buffer.writeln('- **${entry.key}:** $value');
      }
      buffer.writeln(
        '- **Main material:** ${item['isMain'] == true ? 'Yes' : 'No'}',
      );
      buffer.writeln(
        '- **Online:** ${item['isOnline'] == true ? 'Yes' : 'No'}\n',
      );
    }
    return buffer.toString();
  }

  Future<void> _writeGenerated(File file, String content) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  static const _header =
      '<!-- Generated by FPT Knowledge from the local JSON database. '
      'This file may be refreshed during export. -->\n\n';
  static const _personalHeader =
      '<!-- Personal note copied from the read-only FPT Knowledge JSON database. '
      'This file is not overwritten automatically. -->\n\n';

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : const [];
  static String _text(Object? value) => value?.toString().trim() ?? '';
  static String _safe(String value) => value
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  static String _semesterFilename(int semester) =>
      'Semester ${semester.toString().padLeft(2, '0')}';
  static String _join(String first, String second, [String? third]) =>
      third == null
      ? '$first${Platform.pathSeparator}$second'
      : '$first${Platform.pathSeparator}$second${Platform.pathSeparator}$third';
}
