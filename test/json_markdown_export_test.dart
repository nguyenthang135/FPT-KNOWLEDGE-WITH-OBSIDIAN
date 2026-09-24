import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/database/bundled_database_installer.dart';
import 'package:fptu_se_brain/database/database_repository.dart';
import 'package:fptu_se_brain/notes/json_markdown_export_service.dart';
import 'package:fptu_se_brain/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late DatabaseRepository repository;
  late JsonMarkdownExportService exporter;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('json_markdown_export_');
    final database = Directory('${root.path}${Platform.pathSeparator}Database');
    final installer = BundledDatabaseInstaller(
      databaseDirectory: database,
      assetLoader: () async {
        final data = await rootBundle.load(BundledDatabaseInstaller.assetPath);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
    );
    await installer.ensureInstalled();
    repository = DatabaseRepository(database);
    await repository.initialize();
    exporter = JsonMarkdownExportService(
      repository,
      settings: AppSettings.forDirectory(
        Directory('${root.path}${Platform.pathSeparator}Settings'),
      ),
    );
  });

  tearDownAll(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('exports subject from JSON and never overwrites My Notes', () async {
    final vault = Directory(
      '${root.path}${Platform.pathSeparator}SubjectVault',
    );
    await exporter.exportSubject(
      'CEA201',
      curriculumCode: 'BIT_SE_K18D_19A',
      rootDirectory: vault,
    );
    final subjectRoot = Directory(
      '${vault.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}BIT_SE_K18D_19A'
      '${Platform.pathSeparator}Subjects${Platform.pathSeparator}CEA201',
    );
    for (final name in [
      'Overview.md',
      'Assessment.md',
      'Materials.md',
      'My Notes.md',
    ]) {
      expect(
        File('${subjectRoot.path}${Platform.pathSeparator}$name').existsSync(),
        isTrue,
      );
    }
    final notes = File(
      '${subjectRoot.path}${Platform.pathSeparator}My Notes.md',
    );
    await notes.writeAsString('USER CONTENT MUST SURVIVE');
    await exporter.exportSubject(
      'CEA201',
      curriculumCode: 'BIT_SE_K18D_19A',
      rootDirectory: vault,
    );
    expect(await notes.readAsString(), 'USER CONTENT MUST SURVIVE');
    expect(
      await File(
        '${subjectRoot.path}${Platform.pathSeparator}Assessment.md',
      ).readAsString(),
      contains('Final exam'),
    );
  });

  test('exports semester and its subject pages offline', () async {
    final vault = Directory(
      '${root.path}${Platform.pathSeparator}SemesterVault',
    );
    final result = await exporter.exportSemester(
      'BIT_SE_K18D_19A',
      5,
      rootDirectory: vault,
    );
    expect(result, isNotNull);
    expect(result!.exportedSubjects, greaterThan(0));
    final semester = File(
      '${vault.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}BIT_SE_K18D_19A'
      '${Platform.pathSeparator}Semesters${Platform.pathSeparator}Semester 05.md',
    );
    expect(await semester.exists(), isTrue);
    expect(await semester.readAsString(), contains('Semester 5'));
  });

  test('exports whole curriculum with compatible wiki links', () async {
    final vault = Directory(
      '${root.path}${Platform.pathSeparator}CurriculumVault',
    );
    final result = await exporter.exportCurriculum(
      'BIT_SE_K18D_19A',
      rootDirectory: vault,
    );
    expect(result, isNotNull);
    expect(result!.exportedSubjects, greaterThan(30));
    final curriculum = File(
      '${vault.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}BIT_SE_K18D_19A'
      '${Platform.pathSeparator}Curriculum.md',
    );
    final text = await curriculum.readAsString();
    expect(text, contains('BIT_SE_K18D_19A/Subjects/CEA201/Overview'));
    expect(text, isNot(contains('FPT Knowledge/BIT_SE_K18D_19A')));
    expect(
      File(
        '${vault.path}${Platform.pathSeparator}FPT Knowledge'
        '${Platform.pathSeparator}BIT_SE_K18D_19A'
        '${Platform.pathSeparator}.fpt_knowledge_sync.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('My Notes library adds and removes personal copies only', () async {
    final vault = Directory(
      '${root.path}${Platform.pathSeparator}LibraryVault',
    );
    final sourceBefore = await repository.loadSubject('CEA201');

    final firstCea = await exporter.addSubjectToMyNotes(
      'CEA201',
      rootDirectory: vault,
    );
    expect(firstCea?.created, isTrue);
    await exporter.addSubjectToMyNotes('PRM393', rootDirectory: vault);
    await exporter.addCurriculumToMyNotes(
      'BIT_SE_K18D_19A',
      rootDirectory: vault,
    );

    final items = await exporter.listMyNotes(vault);
    expect(
      items.map((item) => item.code),
      containsAll(['CEA201', 'PRM393', 'BIT_SE_K18D_19A']),
    );
    final cea = items.singleWhere((item) => item.code == 'CEA201');
    final ceaFile = await exporter.myNotesFile(vault, cea);
    expect(await ceaFile.readAsString(), contains('## Assessment'));

    await ceaFile.writeAsString('MANUAL EDIT');
    final existingCea = await exporter.addSubjectToMyNotes(
      'CEA201',
      rootDirectory: vault,
    );
    expect(existingCea?.created, isFalse);
    expect(await ceaFile.readAsString(), 'MANUAL EDIT');

    await exporter.removeFromMyNotes(vault, cea);
    expect(
      (await exporter.listMyNotes(vault)).map((item) => item.code),
      isNot(contains('CEA201')),
    );
    expect(await ceaFile.exists(), isFalse);
    expect(await repository.loadSubject('CEA201'), equals(sourceBefore));
  });

  test('curriculum My Notes item creates a linked Obsidian package', () async {
    final vault = Directory(
      '${root.path}${Platform.pathSeparator}LinkedCurriculumVault',
    );
    const code = 'BIT_SE_K19D_K20A';
    final sourceBefore = await repository.loadCurriculum(code);

    final result = await exporter.addCurriculumToMyNotes(
      code,
      rootDirectory: vault,
    );
    expect(result, isNotNull);
    final package = Directory(
      '${vault.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}My Notes'
      '${Platform.pathSeparator}Curricula'
      '${Platform.pathSeparator}$code',
    );
    final curriculum = File(
      '${package.path}${Platform.pathSeparator}Curriculum.md',
    );
    final semester8 = File(
      '${package.path}${Platform.pathSeparator}Semesters'
      '${Platform.pathSeparator}Semester 08.md',
    );
    final prmRoot = Directory(
      '${package.path}${Platform.pathSeparator}Subjects'
      '${Platform.pathSeparator}PRM393',
    );
    expect(await curriculum.exists(), isTrue);
    expect(await semester8.exists(), isTrue);
    for (final name in [
      'Overview.md',
      'Assessment.md',
      'Materials.md',
      'My Notes.md',
    ]) {
      expect(
        File('${prmRoot.path}${Platform.pathSeparator}$name').existsSync(),
        isTrue,
      );
    }
    expect(
      Directory(
        '${package.path}${Platform.pathSeparator}Specialization',
      ).existsSync(),
      isTrue,
    );

    final curriculumText = await curriculum.readAsString();
    expect(curriculumText, contains('[[Subjects/PRM393/Overview|PRM393'));
    expect(curriculumText, isNot(contains('FPT Knowledge/')));
    final semesterText = await semester8.readAsString();
    expect(semesterText, contains('[[../Subjects/PRM393/Overview|PRM393'));

    final userNotes = File(
      '${prmRoot.path}${Platform.pathSeparator}My Notes.md',
    );
    await userNotes.writeAsString('PERSONAL PRM393 NOTES');
    await exporter.addCurriculumToMyNotes(code, rootDirectory: vault);
    expect(await userNotes.readAsString(), 'PERSONAL PRM393 NOTES');

    final items = await exporter.listMyNotes(vault);
    final item = items.singleWhere((item) => item.code == code);
    expect(item.type, MyNotesItemType.curriculum);
    expect(item.relativePath, 'Curricula/$code/Curriculum.md');
    expect(items.where((item) => item.code == code), hasLength(1));

    await exporter.removeFromMyNotes(vault, item);
    expect(await package.exists(), isFalse);
    expect(await repository.containsCurriculum(code), isTrue);
    final sourceAfter = await repository.loadCurriculum(code);
    expect(sourceAfter?.subjects.length, sourceBefore?.subjects.length);
  });
}
