import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/ai/ask_fpt_controller.dart';
import 'package:fptu_se_brain/ai/ask_fpt_planner.dart';
import 'package:fptu_se_brain/ai/groq_ai_service.dart';
import 'package:fptu_se_brain/database/bundled_database_installer.dart';
import 'package:fptu_se_brain/database/database_repository.dart';
import 'package:fptu_se_brain/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory suiteRoot;
  late DatabaseRepository repository;

  setUpAll(() async {
    suiteRoot = await Directory.systemTemp.createTemp('phase35_');
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
    'legacy specialization without provenance migrates to unknown',
    () async {
      final directory = await Directory.systemTemp.createTemp('legacy_spec_');
      addTearDown(() => directory.delete(recursive: true));
      final java = (await repository.loadSpecializations(
        'BIT_SE_K19D_K20A',
      )).firstWhere((item) => item.name.contains('SE_COM10.2'));
      await File(
        '${directory.path}${Platform.pathSeparator}app_settings.json',
      ).writeAsString(
        jsonEncode({
          'currentCurriculum': 'BIT_SE_K19D_K20A',
          'activeContextProvenance': 'explicitUseSelection',
          'specializationsByCurriculum': {
            'BIT_SE_K19D_K20A': {
              'name': java.name,
              'note': java.note,
              'detailUrl': java.detailUrl,
              'subjects': [
                for (final subject in java.subjects)
                  {
                    'code': subject.code,
                    'name': subject.name,
                    'semester': subject.semester,
                  },
              ],
            },
          },
        }),
      );
      final settings = AppSettings.forDirectory(directory);
      final controller = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();

      expect(await settings.getSpecialization('BIT_SE_K19D_K20A'), isNull);
      expect(
        await settings.getSpecializationProvenance('BIT_SE_K19D_K20A'),
        SpecializationProvenance.none,
      );
      final response = await controller.ask('tôi học gì kỳ 8?');
      expect(response.state, AskFptResponseState.clarification);
      expect(response.content.actions, isNotEmpty);
      expect(response.retrievedContext?['specializationMissing'], isTrue);
      expect(response.retrievedContext?['subjects'], isNotEmpty);
    },
  );

  test('lists real options, changes specialization, and clears it', () async {
    final directory = await Directory.systemTemp.createTemp('spec_commands_');
    addTearDown(() => directory.delete(recursive: true));
    final settings = AppSettings.forDirectory(directory);
    final controller = AskFptController(
      repository,
      settings: settings,
      groq: GroqAiService(apiKey: ''),
    );
    await controller.initialize();
    await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');

    final options = await controller.ask(
      'chương trình này có những chuyên ngành nào?',
    );
    final labels = options.content.actions.map((item) => item.label).toList();
    expect(labels, containsAll(['Java chuyên sâu', 'Phát triển game']));

    await controller.ask('chuyên ngành của tôi là Java chuyên sâu');
    final javaSemester = await controller.ask('kỳ 8 tôi học gì?');
    final javaCodes = _subjectCodes(javaSemester);
    expect(javaCodes, contains('MSS301'));

    await controller.ask('không phải Java, tôi học Game');
    final gameSemester = await controller.ask('kỳ 8 tôi học gì?');
    final gameCodes = _subjectCodes(gameSemester);
    expect(gameCodes, contains('GNS301'));
    expect(gameCodes, isNot(contains('MSS301')));
    expect(
      await settings.getSpecializationProvenance('BIT_SE_K19D_K20A'),
      SpecializationProvenance.explicitUserSelection,
    );

    final restarted = AskFptController(
      repository,
      settings: settings,
      groq: GroqAiService(apiKey: ''),
    );
    await restarted.initialize();
    expect(
      await settings.getSpecializationProvenance('BIT_SE_K19D_K20A'),
      SpecializationProvenance.restoredExplicitSelection,
    );
    expect(
      _subjectCodes(await restarted.ask('kỳ 8 tôi học gì?')),
      contains('GNS301'),
    );

    final invalid = await controller.ask('đổi chuyên ngành sang Blockchain');
    final afterInvalid = await settings.getSpecialization('BIT_SE_K19D_K20A');
    expect(
      invalid.state,
      AskFptResponseState.clarification,
      reason: afterInvalid?.name,
    );
    expect(
      (await settings.getSpecialization('BIT_SE_K19D_K20A'))?.name,
      contains('SE_COM12'),
    );

    await controller.ask('bỏ chuyên ngành hiện tại');
    expect(await settings.getSpecialization('BIT_SE_K19D_K20A'), isNull);
    final unknown = await controller.ask('chuyên ngành của tôi là gì?');
    expect(unknown.state, AskFptResponseState.clarification);
  });

  test(
    'planner handles natural comparison with narrow local retrieval',
    () async {
      final directory = await Directory.systemTemp.createTemp('planner_');
      addTearDown(() => directory.delete(recursive: true));
      final controller = AskFptController(
        repository,
        settings: AppSettings.forDirectory(directory),
        groq: GroqAiService(apiKey: ''),
        planner: const _FixedPlanner(
          AskFptPlan(
            domain: 'fpt_knowledge',
            intent: 'compare_specialization_and_core',
            requiresCurriculum: true,
            requiresSpecialization: true,
            retrievalTargets: ['curriculum', 'specialization'],
          ),
        ),
      );
      await controller.initialize();
      await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');
      await controller.ask('chuyên ngành của tôi là Phát triển game');

      final response = await controller.ask(
        'ngoài mấy môn chuyên ngành thì tôi còn phải học gì nữa?',
      );
      expect(controller.lastPlan?.retrievalTargets, [
        'curriculum',
        'specialization',
      ]);
      expect(response.retrievedContext?.keys, {
        'displayName',
        'specialization',
        'coreSubjects',
        'specializationSubjects',
      });
      expect(response.retrievedContext?['coreSubjects'], isNotEmpty);
      expect(response.retrievedContext?['specializationSubjects'], isNotEmpty);
    },
  );

  test('planner returns a short clarification for genuine ambiguity', () async {
    final directory = await Directory.systemTemp.createTemp('clarify_');
    addTearDown(() => directory.delete(recursive: true));
    final controller = AskFptController(
      repository,
      settings: AppSettings.forDirectory(directory),
      groq: GroqAiService(apiKey: ''),
      planner: const _FixedPlanner(
        AskFptPlan(
          domain: 'fpt_knowledge',
          intent: 'unclear',
          clarificationNeeded: true,
          clarificationQuestion: 'Bạn muốn xem môn học hay học kỳ?',
        ),
      ),
    );
    await controller.initialize();
    final response = await controller.ask('việc học của mình thì sao?');
    expect(response.state, AskFptResponseState.clarification);
    expect(response.text, 'Bạn muốn xem môn học hay học kỳ?');
    expect(response.retrievedContext, isNull);
  });

  test(
    'Groq parser extracts structured JSON and blocks protocol fragments',
    () async {
      final structured = jsonEncode({
        'title': 'Học kỳ 8',
        'summary': 'An toàn',
        'sections': <Object>[],
      });
      for (final raw in [
        structured,
        '```json\n$structured\n```',
        'Đây là kết quả:\n$structured\nHết.',
        'response: $structured',
      ]) {
        final answer = await _serviceReturning(
          raw,
        ).answer(question: 'test', context: const {}, english: false);
        expect(answer.structured?['title'], 'Học kỳ 8', reason: raw);
      }

      for (final raw in ['{"title":"dang dở"', '{invalid json}']) {
        final answer = await _serviceReturning(
          raw,
        ).answer(question: 'test', context: const {}, english: false);
        expect(answer.isSuccess, isFalse, reason: raw);
        expect(answer.failure, GroqFailureKind.invalidResponse);
      }

      final plain = await _serviceReturning(
        '**Câu trả lời**<br>---\n| Môn | Kỳ |\n|---|---|\n| MSS301 | 8 |',
      ).answer(question: 'test', context: const {}, english: false);
      expect(plain.isSuccess, isTrue);
      expect(plain.text, isNot(contains('**')));
      expect(plain.text, isNot(contains('<br>')));
      expect(plain.text, isNot(contains('---')));
      expect(plain.text, isNot(contains('|')));
    },
  );

  test(
    'controller replaces unusable protocol output with controlled text',
    () async {
      final directory = await Directory.systemTemp.createTemp('format_guard_');
      addTearDown(() => directory.delete(recursive: true));
      final controller = AskFptController(
        repository,
        settings: AppSettings.forDirectory(directory),
        groq: _serviceReturning('{"title":"dang dở"'),
      );
      await controller.initialize();
      final response = await controller.ask('CEA201 là môn gì?');
      expect(response.state, AskFptResponseState.apiError);
      expect(
        response.text,
        'Mình chưa thể trình bày câu trả lời này đúng định dạng. Hãy thử hỏi lại ngắn hơn.',
      );
      expect(response.text, isNot(contains('{')));
    },
  );
}

List<Object?> _subjectCodes(AskFptResponse response) =>
    (response.retrievedContext?['subjects'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item['code'])
        .toList();

GroqAiService _serviceReturning(String content) => GroqAiService(
  apiKey: 'test-key',
  transport: (_, _, _) async => GroqHttpResponse(
    200,
    jsonEncode({
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    }),
  ),
);

class _FixedPlanner implements AskFptPlanner {
  final AskFptPlan value;

  const _FixedPlanner(this.value);

  @override
  Future<AskFptPlan?> plan({
    required String question,
    required Map<String, dynamic> knownContext,
    required bool english,
  }) async => value;
}
