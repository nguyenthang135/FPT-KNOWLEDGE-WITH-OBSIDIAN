import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/ai/ask_fpt_controller.dart';
import 'package:fptu_se_brain/ai/groq_ai_service.dart';
import 'package:fptu_se_brain/database/bundled_database_installer.dart';
import 'package:fptu_se_brain/database/database_repository.dart';
import 'package:fptu_se_brain/notes/json_markdown_export_service.dart';
import 'package:fptu_se_brain/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory suiteRoot;
  late DatabaseRepository repository;

  setUpAll(() async {
    suiteRoot = await Directory.systemTemp.createTemp('phase36_');
    final databaseRoot = Directory(
      '${suiteRoot.path}${Platform.pathSeparator}Database',
    );
    await BundledDatabaseInstaller(
      databaseDirectory: databaseRoot,
      assetLoader: () async {
        final data = await rootBundle.load(BundledDatabaseInstaller.assetPath);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
    ).ensureInstalled();
    repository = DatabaseRepository(databaseRoot);
    await repository.initialize();
  });

  tearDownAll(() async {
    if (await suiteRoot.exists()) await suiteRoot.delete(recursive: true);
  });

  test(
    'personal semester question without verified profile asks MSSV',
    () async {
      final directory = await Directory.systemTemp.createTemp('phase36_id_');
      addTearDown(() => directory.delete(recursive: true));
      final controller = AskFptController(
        repository,
        settings: AppSettings.forDirectory(directory),
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();

      final response = await controller.ask('kỳ 5 tôi học những môn nào?');

      expect(response.state, AskFptResponseState.needsStudentContext);
      expect(response.text, contains('MSSV'));
      expect(controller.studentContext.curriculum, isNull);
    },
  );

  test(
    'professional specialization classifier removes PE and language tracks',
    () async {
      final values = await repository.loadProfessionalSpecializations(
        'BIT_SE_K19D_K20A',
      );
      final names = values.map((value) => value.name).join('\n');

      expect(names, contains('Intensive Java'));
      expect(names, contains('Game Development'));
      expect(names, isNot(contains('PHE_COM')));
      expect(names, isNot(contains('Vovinam')));
      expect(names, isNot(contains('Cờ vua')));
      expect(names, isNot(contains('Japanese Bridge Engineer')));
      expect(names, isNot(contains('Korean Language')));
    },
  );

  test(
    'unknown specialization shows core semester subjects and valid choices',
    () async {
      final directory = await Directory.systemTemp.createTemp('phase36_core_');
      addTearDown(() => directory.delete(recursive: true));
      final controller = AskFptController(
        repository,
        settings: AppSettings.forDirectory(directory),
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();
      await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');

      final response = await controller.ask('kỳ 5 tôi học những môn nào?');
      final codes = _subjectCodes(response);
      final labels = response.content.actions
          .map((action) => action.label)
          .toList();

      expect(response.state, AskFptResponseState.clarification);
      expect(codes, containsAll(['SWP391', 'SWR302', 'SWT301', 'WDU203c']));
      expect(codes, isNot(contains('HSF302')));
      expect(response.text, contains('chưa bao gồm các môn chuyên ngành'));
      expect(response.text, contains('học kỳ 5'));
      expect(labels, containsAll(['Java chuyên sâu', 'Phát triển game']));
      expect(labels, isNot(contains('Vovinam')));
      expect(labels, isNot(contains('Cờ vua')));
    },
  );

  test(
    'explicit Java selection is reused for semester 5 without asking again',
    () async {
      final directory = await Directory.systemTemp.createTemp('phase36_java_');
      addTearDown(() => directory.delete(recursive: true));
      final settings = AppSettings.forDirectory(directory);
      final controller = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();
      await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');

      final selected = await controller.ask(
        'chuyên ngành của tôi là Java chuyên sâu',
      );
      final semester = await controller.ask('kỳ 5 tôi học những môn nào?');

      expect(selected.text, contains('Java chuyên sâu'));
      expect(semester.state, AskFptResponseState.answered);
      expect(_subjectCodes(semester), contains('HSF302'));
      expect(semester.text, isNot(contains('Bạn đang theo chuyên ngành nào')));
      expect(
        controller.studentContext.specializationProvenance,
        SpecializationProvenance.explicitUserSelection,
      );
      expect(
        await settings.getSpecializationProvenance('BIT_SE_K19D_K20A'),
        SpecializationProvenance.explicitUserSelection,
      );
    },
  );

  test(
    'named professional specialization resolves directly and locally',
    () async {
      final directory = await Directory.systemTemp.createTemp('phase36_named_');
      addTearDown(() => directory.delete(recursive: true));
      final controller = AskFptController(
        repository,
        settings: AppSettings.forDirectory(directory),
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();
      await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');

      final response = await controller.ask(
        'Phát triển game có những môn nào?',
      );

      expect(response.state, AskFptResponseState.answered);
      expect(
        _subjectCodes(response),
        containsAll(['FGU301', 'AGU301', 'GDC301', 'GNS301']),
      );
      expect(response.text, isNot(contains('cho biết tên chuyên ngành')));
      expect(controller.studentContext.specialization, isNull);
    },
  );

  test(
    'clear note phrases always execute the deterministic note action',
    () async {
      final directory = await Directory.systemTemp.createTemp('phase36_notes_');
      addTearDown(() => directory.delete(recursive: true));
      final exporter = _RecordingNotesExporter(repository);
      final controller = AskFptController(
        repository,
        settings: AppSettings.forDirectory(directory),
        groq: GroqAiService(apiKey: ''),
        exporter: exporter,
      );
      await controller.initialize();

      for (final phrase in [
        'cho tôi note của môn SBA',
        'tạo note SBA',
        'mình cần note SBA',
        'lưu SBA vào My Notes',
      ]) {
        final response = await controller.ask(phrase);
        expect(
          response.state,
          AskFptResponseState.notesSuccess,
          reason: phrase,
        );
        expect(
          response.content.actions.map((action) => action.type),
          containsAll([
            AskFptActionType.viewMyNotes,
            AskFptActionType.openObsidian,
          ]),
        );
      }
      expect(exporter.subjectCodes, everyElement('SBA301'));
      expect(exporter.subjectCodes, hasLength(4));
    },
  );

  test('existing note returns handoff without duplicate semantics', () async {
    final directory = await Directory.systemTemp.createTemp(
      'phase36_existing_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final exporter = _RecordingNotesExporter(repository, created: false);
    final controller = AskFptController(
      repository,
      settings: AppSettings.forDirectory(directory),
      groq: GroqAiService(apiKey: ''),
      exporter: exporter,
    );
    await controller.initialize();

    final response = await controller.ask('cho tôi note môn SBA');

    expect(response.state, AskFptResponseState.notesSuccess);
    expect(response.text, contains('đã có trong My Notes'));
    expect(exporter.subjectCodes, ['SBA301']);
  });

  test(
    'whole curriculum is constructed locally without Groq serialization',
    () async {
      final directory = await Directory.systemTemp.createTemp('phase36_large_');
      addTearDown(() => directory.delete(recursive: true));
      var groqCalls = 0;
      final groq = GroqAiService(
        apiKey: 'test',
        transport: (_, _, _) async {
          groqCalls++;
          return GroqHttpResponse(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{broken'},
                },
              ],
            }),
          );
        },
      );
      final controller = AskFptController(
        repository,
        settings: AppSettings.forDirectory(directory),
        groq: groq,
      );
      await controller.initialize();
      await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');

      final response = await controller.ask(
        'chương trình của tôi gồm những môn nào?',
      );

      expect(response.state, AskFptResponseState.answered);
      expect(groqCalls, 0);
      expect(
        response.content.sections.length,
        greaterThan(8),
        reason: '${response.source} ${response.retrievedContext?.keys}',
      );
      expect(response.text, isNot(contains('thử hỏi lại ngắn hơn')));
      expect(response.text, isNot(contains('{')));
    },
  );

  test(
    'switching student curriculum clears incompatible semester and specialization',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'phase36_switch_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final settings = AppSettings.forDirectory(directory);
      final controller = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();
      await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');
      await controller.ask('chuyên ngành của tôi là Java chuyên sâu');
      controller.currentSemester = 5;
      await settings.setCurrentSemester(5);

      await controller.ask('AI193911');

      expect(controller.studentContext.curriculum, startsWith('BIT_AI_'));
      expect(controller.studentContext.currentSemester, isNull);
      expect(controller.studentContext.specialization, isNull);
      expect(
        controller.studentContext.curriculumProvenance,
        ActiveContextProvenance.studentIdResolved,
      );
    },
  );

  test(
    'invalid specialization is not saved for the active curriculum',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'phase36_invalid_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final settings = AppSettings.forDirectory(directory);
      final controller = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();
      await controller.selectActiveCurriculum('BIT_SE_K17D_18A');
      final curriculum = controller.studentContext.curriculum!;

      final response = await controller.ask('tôi học Game');

      expect(response.state, AskFptResponseState.clarification);
      expect(await settings.getSpecialization(curriculum), isNull);
      expect(controller.studentContext.specialization, isNull);
    },
  );

  test('ambiguous major statement asks what SE means', () async {
    final directory = await Directory.systemTemp.createTemp(
      'phase36_ambiguous_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final controller = AskFptController(
      repository,
      settings: AppSettings.forDirectory(directory),
      groq: GroqAiService(apiKey: ''),
    );
    await controller.initialize();

    final response = await controller.ask('tôi học SE');

    expect(response.state, AskFptResponseState.clarification);
    expect(response.text, contains('Software Engineering'));
    expect(response.retrievedContext, isNull);
  });
}

List<Object?> _subjectCodes(AskFptResponse response) =>
    (response.retrievedContext?['subjects'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item['code'])
        .toList();

class _RecordingNotesExporter extends JsonMarkdownExportService {
  final bool created;
  final List<String> subjectCodes = [];

  _RecordingNotesExporter(super.repository, {this.created = true});

  @override
  Future<MarkdownExportResult?> addSubjectToMyNotes(
    String subjectCode, {
    Directory? rootDirectory,
  }) async {
    subjectCodes.add(subjectCode);
    return MarkdownExportResult(
      path: 'C:\\FPT Knowledge\\My Notes\\Subjects\\$subjectCode.md',
      exportedSubjects: 1,
      created: created,
    );
  }
}
