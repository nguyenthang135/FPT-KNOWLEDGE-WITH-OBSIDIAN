import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/flm/flm_combo_service.dart';
import 'package:fptu_se_brain/obsidian/obsidian_service.dart';

void main() {
  late Directory temporaryDirectory;
  late ObsidianService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'fpt_knowledge_sync_test_',
    );
    service = ObsidianService();
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('reports a missing selected folder', () async {
    final inspection = await service.inspectCurriculumSync(
      knowledgeFolderPath: '${temporaryDirectory.path}/missing',
      curriculumCode: 'BIT_SE_K18D_19A',
      specialization: null,
    );

    expect(inspection.folderAvailable, isFalse);
    expect(inspection.needsSync, isTrue);
  });

  test('reports a missing manifest as needing sync', () async {
    await Directory(
      '${temporaryDirectory.path}/FPT Knowledge/BIT_SE_K18D_19A',
    ).create(recursive: true);

    final inspection = await service.inspectCurriculumSync(
      knowledgeFolderPath: temporaryDirectory.path,
      curriculumCode: 'BIT_SE_K18D_19A',
      specialization: null,
    );

    expect(inspection.folderAvailable, isTrue);
    expect(inspection.needsSync, isTrue);
  });

  test('accepts a readable manifest matching the specialization', () async {
    final curriculumDirectory = Directory(
      '${temporaryDirectory.path}/FPT Knowledge/BIT_SE_K18D_19A',
    );
    await curriculumDirectory.create(recursive: true);

    await File(
      '${curriculumDirectory.path}/.fpt_knowledge_sync.json',
    ).writeAsString(
      jsonEncode({
        'version': 1,
        'specializationName': 'Intensive Java',
        'specializationSubjectCodes': ['HSF302', 'SBA301'],
      }),
    );

    const specialization = SpecializationCombo(
      name: 'Intensive Java',
      note: '',
      detailUrl: '',
      subjects: [
        ComboSubject(code: 'SBA301', name: 'SBA', semester: 7),
        ComboSubject(code: 'HSF302', name: 'HSF', semester: 5),
      ],
    );

    await _createGeneratedStructure(
      curriculumDirectory,
      specialization: specialization,
    );

    final inspection = await service.inspectCurriculumSync(
      knowledgeFolderPath: temporaryDirectory.path,
      curriculumCode: 'BIT_SE_K18D_19A',
      specialization: specialization,
    );

    expect(inspection.folderAvailable, isTrue);
    expect(inspection.needsSync, isFalse);
  });

  test('rejects a manifest when generated files are incomplete', () async {
    final curriculumDirectory = Directory(
      '${temporaryDirectory.path}/FPT Knowledge/BIT_SE_K18D_19A',
    );
    await curriculumDirectory.create(recursive: true);
    await File(
      '${curriculumDirectory.path}/.fpt_knowledge_sync.json',
    ).writeAsString(
      jsonEncode({
        'version': 1,
        'specializationName': null,
        'specializationSubjectCodes': <String>[],
      }),
    );

    final inspection = await service.inspectCurriculumSync(
      knowledgeFolderPath: temporaryDirectory.path,
      curriculumCode: 'BIT_SE_K18D_19A',
      specialization: null,
    );

    expect(inspection.needsSync, isTrue);
    expect(inspection.message, contains('required generated files'));
  });

  test('detects a specialization mismatch', () async {
    final curriculumDirectory = Directory(
      '${temporaryDirectory.path}/FPT Knowledge/BIT_SE_K18D_19A',
    );
    await curriculumDirectory.create(recursive: true);

    await File(
      '${curriculumDirectory.path}/.fpt_knowledge_sync.json',
    ).writeAsString(
      jsonEncode({
        'version': 1,
        'specializationName': 'Old specialization',
        'specializationSubjectCodes': ['OLD101'],
      }),
    );

    const specialization = SpecializationCombo(
      name: 'Intensive Java',
      note: '',
      detailUrl: '',
      subjects: [ComboSubject(code: 'HSF302', name: 'HSF', semester: 5)],
    );

    final inspection = await service.inspectCurriculumSync(
      knowledgeFolderPath: temporaryDirectory.path,
      curriculumCode: 'BIT_SE_K18D_19A',
      specialization: specialization,
    );

    expect(inspection.needsSync, isTrue);
  });
}

Future<void> _createGeneratedStructure(
  Directory curriculumDirectory, {
  required SpecializationCombo specialization,
}) async {
  await File('${curriculumDirectory.path}/Curriculum.md').writeAsString('#');
  final semesters = Directory('${curriculumDirectory.path}/Semesters');
  await semesters.create(recursive: true);
  await File('${semesters.path}/Semester 5.md').writeAsString('#');

  final subjects = Directory('${curriculumDirectory.path}/Subjects');
  for (final subject in specialization.subjects) {
    final directory = Directory('${subjects.path}/${subject.code}');
    await directory.create(recursive: true);
    for (final filename in const [
      'Overview.md',
      'Assessment.md',
      'Materials.md',
    ]) {
      await File('${directory.path}/$filename').writeAsString('#');
    }
  }

  final specializationDirectory = Directory(
    '${curriculumDirectory.path}/Specialization',
  );
  await specializationDirectory.create(recursive: true);
  await File(
    '${specializationDirectory.path}/Intensive Java.md',
  ).writeAsString('#');
}
