import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fptu_se_brain/obsidian/obsidian_note_repository.dart';

void main() {
  test('Reads My Notes.md from the selected subject folder', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'fpt_knowledge_test_',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final notesFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}BIT_SE_K18D_19A'
      '${Platform.pathSeparator}Subjects'
      '${Platform.pathSeparator}PRM393'
      '${Platform.pathSeparator}My Notes.md',
    );
    await notesFile.parent.create(recursive: true);
    await notesFile.writeAsString('StatefulWidget dùng khi UI thay đổi.');

    final repository = ObsidianNoteRepository(
      vaultPathProvider: () async => temporaryDirectory.path,
    );
    final result = await repository.readMyNotes(
      curriculumCode: 'BIT_SE_K18D_19A',
      subjectCode: 'PRM393',
    );

    expect(result.hasNotes, isTrue);
    expect(result.notes, contains('StatefulWidget'));
  });
}
