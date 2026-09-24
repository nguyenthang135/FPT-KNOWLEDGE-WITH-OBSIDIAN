import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/database/database_repository.dart';
import 'package:fptu_se_brain/notes/json_markdown_export_service.dart';
import 'package:fptu_se_brain/obsidian/obsidian_desktop_service.dart';
import 'package:fptu_se_brain/screens/my_notes_view.dart';

void main() {
  testWidgets('My Notes starts as a library and hosts only after item open', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('my_notes_library_');
    addTearDown(() => root.deleteSync(recursive: true));
    final note = File(
      '${root.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}My Notes'
      '${Platform.pathSeparator}Subjects'
      '${Platform.pathSeparator}PRM393.md',
    );
    note.parent.createSync(recursive: true);
    note.writeAsStringSync('# PRM393');
    final exportService = _FakeExportService(note);
    final desktopService = _FakeDesktopService();
    String? hostedFilePath;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyNotesView(
            exportService: exportService,
            folderPath: root.path,
            onChooseFolder: () async => root.path,
            desktopService: desktopService,
            hostBuilder: (vaultPath, filePath) {
              hostedFilePath = filePath;
              return const Text('Hosted note surface');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('PRM393'), findsOneWidget);
    expect(find.text('Open in Obsidian'), findsOneWidget);
    expect(find.text('Hosted note surface'), findsNothing);

    await tester.tap(find.text('Open in Obsidian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('Back to My Notes'), findsOneWidget);
    expect(find.text('Hosted note surface'), findsOneWidget);
    expect(hostedFilePath, note.path);

    await tester.tap(find.text('Back to My Notes'));
    await tester.pump();

    expect(find.text('Hosted note surface'), findsNothing);
    expect(find.text('PRM393'), findsOneWidget);
  });

  testWidgets('missing Obsidian offers download and check-again flow', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('my_notes_missing_');
    addTearDown(() => root.deleteSync(recursive: true));
    final note = File(
      '${root.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}My Notes'
      '${Platform.pathSeparator}Subjects'
      '${Platform.pathSeparator}PRM393.md',
    );
    note.parent.createSync(recursive: true);
    note.writeAsStringSync('# PRM393');
    final desktopService = _FakeDesktopService(installed: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyNotesView(
            exportService: _FakeExportService(note),
            folderPath: root.path,
            onChooseFolder: () async => root.path,
            desktopService: desktopService,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Open in Obsidian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('Download Obsidian'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Hosted note surface'), findsNothing);
  });

  testWidgets('curriculum item opens its Curriculum.md entry point', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('curriculum_entry_');
    addTearDown(() => root.deleteSync(recursive: true));
    const code = 'BIT_SE_K19D_K20A';
    final entry = File(
      '${root.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}My Notes'
      '${Platform.pathSeparator}Curricula'
      '${Platform.pathSeparator}$code'
      '${Platform.pathSeparator}Curriculum.md',
    );
    entry.parent.createSync(recursive: true);
    entry.writeAsStringSync('# $code');
    String? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyNotesView(
            exportService: _FakeExportService(
              entry,
              item: const MyNotesLibraryItem(
                type: MyNotesItemType.curriculum,
                code: code,
                title: 'Software Engineering K19',
                relativePath: 'Curricula/$code/Curriculum.md',
              ),
            ),
            folderPath: root.path,
            onChooseFolder: () async => root.path,
            desktopService: _FakeDesktopService(),
            hostBuilder: (vaultPath, filePath) {
              opened = filePath;
              return const Text('Curriculum hosted');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Open in Obsidian'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(opened, entry.path);
    expect(find.text('Curriculum hosted'), findsOneWidget);
  });

  testWidgets('Ask FPT handoff opens the exact registered note', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('ask_fpt_handoff_');
    addTearDown(() => root.deleteSync(recursive: true));
    final note = File(
      '${root.path}${Platform.pathSeparator}FPT Knowledge'
      '${Platform.pathSeparator}My Notes'
      '${Platform.pathSeparator}Subjects'
      '${Platform.pathSeparator}PRM393.md',
    );
    note.parent.createSync(recursive: true);
    note.writeAsStringSync('# PRM393');
    String? opened;
    var handled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyNotesView(
            exportService: _FakeExportService(note),
            folderPath: root.path,
            onChooseFolder: () async => root.path,
            desktopService: _FakeDesktopService(),
            openItemId: 'subject:PRM393',
            onItemRequestHandled: () => handled = true,
            hostBuilder: (vaultPath, filePath) {
              opened = filePath;
              return const Text('Ask FPT exact note');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(handled, isTrue);
    expect(opened, note.path);
    expect(find.text('Ask FPT exact note'), findsOneWidget);
  });
}

class _FakeExportService extends JsonMarkdownExportService {
  _FakeExportService(
    this.file, {
    this.item = const MyNotesLibraryItem(
      type: MyNotesItemType.subject,
      code: 'PRM393',
      title: 'Mobile Programming',
      relativePath: 'Subjects/PRM393.md',
    ),
  }) : super(DatabaseRepository(Directory.systemTemp));

  final File file;
  final MyNotesLibraryItem item;

  @override
  Future<List<MyNotesLibraryItem>> listMyNotes(Directory rootDirectory) async {
    return [item];
  }

  @override
  Future<File> myNotesFile(
    Directory rootDirectory,
    MyNotesLibraryItem item,
  ) async {
    return file;
  }
}

class _FakeDesktopService extends ObsidianDesktopService {
  _FakeDesktopService({this.installed = true});

  final bool installed;
  @override
  Future<bool> isInstalled() async => installed;

  @override
  Future<void> openDownloadPage() async {}

  @override
  Future<ObsidianHostStatus> startHosting({
    required String vaultPath,
    required String filePath,
    required ObsidianHostBounds bounds,
  }) async {
    return const ObsidianHostStatus(
      state: ObsidianHostState.hosted,
      message: 'Hosted',
    );
  }

  @override
  Future<ObsidianHostStatus> updateHostBounds(ObsidianHostBounds bounds) async {
    return const ObsidianHostStatus(
      state: ObsidianHostState.hosted,
      message: 'Hosted',
    );
  }

  @override
  Future<void> hideHost() async {}

  @override
  Future<void> focusHost() async {}
}
