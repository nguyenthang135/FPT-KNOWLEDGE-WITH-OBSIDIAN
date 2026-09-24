import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/ai/ask_fpt_controller.dart';
import 'package:fptu_se_brain/ai/ask_fpt_intent_resolver.dart';
import 'package:fptu_se_brain/ai/groq_ai_service.dart';
import 'package:fptu_se_brain/ai/student_profile_resolver.dart';
import 'package:fptu_se_brain/database/bundled_database_installer.dart';
import 'package:fptu_se_brain/database/database_repository.dart';
import 'package:fptu_se_brain/notes/json_markdown_export_service.dart';
import 'package:fptu_se_brain/screens/ask_fpt_screen.dart';
import 'package:fptu_se_brain/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseRoot;
  late Directory suiteRoot;
  late DatabaseRepository repository;

  setUpAll(() async {
    suiteRoot = await Directory.systemTemp.createTemp('phase3_ask_fpt_');
    databaseRoot = Directory(
      '${suiteRoot.path}${Platform.pathSeparator}Database',
    );
    final installer = BundledDatabaseInstaller(
      databaseDirectory: databaseRoot,
      assetLoader: () async {
        final data = await rootBundle.load(BundledDatabaseInstaller.assetPath);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
    );
    await installer.ensureInstalled();
    repository = DatabaseRepository(databaseRoot);
    await repository.initialize();
  });

  tearDownAll(() async {
    if (await suiteRoot.exists()) await suiteRoot.delete(recursive: true);
  });

  test('routes direct, personal, notes, and unrelated questions', () {
    const resolver = AskFptIntentResolver();
    expect(
      resolver.resolve('HSF có thi PE không?').intent,
      AskFptIntent.subjectAssessment,
    );
    expect(resolver.resolve('HSF có thi PE không?').personal, isFalse);
    expect(
      resolver.resolve('Kỳ 5 tôi học gì?').intent,
      AskFptIntent.semesterSubjects,
    );
    expect(resolver.resolve('Kỳ 5 tôi học gì?').personal, isTrue);
    expect(
      resolver.resolve('Thêm CEA201 vào ghi chú').intent,
      AskFptIntent.notesAddSubject,
    );
    for (final question in [
      'cho tôi biết về những môn tôi sẽ học',
      'tôi sẽ học những môn nào',
      'chương trình của tôi gồm những môn nào',
      'show me the subjects in my program',
    ]) {
      expect(
        resolver.resolve(question).intent,
        AskFptIntent.personalCurriculumSubjects,
        reason: question,
      );
    }
    expect(
      resolver.resolve('PRM393 prerequisite là gì?').intent,
      AskFptIntent.subjectPrerequisite,
    );
    expect(
      resolver.resolve('Messi hay Ronaldo?').intent,
      AskFptIntent.outOfScope,
    );
  });

  test('parses student IDs locally and rejects invalid values', () {
    final resolver = StudentProfileResolver(repository);
    expect(resolver.parse('SE193911')?.majorPrefix, 'SE');
    expect(resolver.parse('SE193911')?.cohort, 19);
    expect(resolver.parse('se 188183')?.cohort, 18);
    expect(resolver.parse('AI19-12345')?.majorPrefix, 'AI');
    expect(resolver.parse('not-an-id'), isNull);
  });

  test('resolves real SE cohort variants without user selection', () async {
    final resolver = StudentProfileResolver(repository);
    final profile = await resolver.resolve(resolver.parse('SE193911')!);
    expect(profile, isNotNull);
    expect(profile!.candidates, containsAll(['BIT_SE_K19B', 'BIT_SE_K19C']));
    expect(profile.primaryCurriculum, 'BIT_SE_K19D_K20A');
    expect(profile.commonSubjectCodes, isNotEmpty);
  });

  test('variant ranking prefers completeness then newest provenance', () {
    final ranked = StudentProfileResolver.rankCandidates([
      CurriculumCandidateSummary(
        code: 'K19D_INCOMPLETE',
        completeness: 20,
        sourceTime: DateTime.utc(2026, 3),
      ),
      CurriculumCandidateSummary(
        code: 'K19B',
        completeness: 48,
        sourceTime: DateTime.utc(2026, 1),
      ),
      CurriculumCandidateSummary(
        code: 'K19C',
        completeness: 48,
        sourceTime: DateTime.utc(2026, 2),
      ),
    ]);
    expect(ranked.map((item) => item.code), [
      'K19C',
      'K19B',
      'K19D_INCOMPLETE',
    ]);
  });

  test('direct subject retrieval never requests student ID', () async {
    final settingsDirectory = await Directory.systemTemp.createTemp(
      'ask_settings_',
    );
    addTearDown(() => settingsDirectory.delete(recursive: true));
    final controller = AskFptController(
      repository,
      settings: AppSettings.forDirectory(settingsDirectory),
      groq: GroqAiService(apiKey: ''),
    );
    await controller.initialize();

    final cea = await controller.ask('CEA201 là môn gì?');
    expect(cea.state, AskFptResponseState.offline);
    expect(cea.source, startsWith('CEA201'));
    expect(cea.text, isNot(contains('MSSV')));
    expect(cea.retrievedContext?.keys, contains('description'));
    expect(cea.retrievedContext?.keys, isNot(contains('assessments')));
    expect(cea.content.title, contains('CEA201'));
    expect(
      cea.content.sections.map((section) => section.type),
      contains(AskFptSectionType.keyValue),
    );

    final hsf = await controller.ask('HSF có thi PE không?');
    expect(hsf.source, startsWith('HSF302'));
    expect(hsf.text, contains('Practical Exam'));
    expect(hsf.text, isNot(contains('MSSV')));
    expect(hsf.content.sections.single.type, AskFptSectionType.assessmentList);

    final prerequisite = await controller.ask('PRF192 có prerequisite không?');
    expect(prerequisite.source, startsWith('PRF192'));

    final materials = await controller.ask('CEA201 có tài liệu gì?');
    expect(
      materials.content.sections.single.type,
      AskFptSectionType.bulletList,
    );
  });

  test(
    'personal questions request ID then persist automatic resolution',
    () async {
      final settingsDirectory = await Directory.systemTemp.createTemp(
        'profile_settings_',
      );
      addTearDown(() => settingsDirectory.delete(recursive: true));
      final settings = AppSettings.forDirectory(settingsDirectory);
      final controller = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();

      final needsId = await controller.ask('Kỳ 5 tôi học gì?');
      expect(needsId.state, AskFptResponseState.needsStudentContext);
      final resolved = await controller.ask('SE193911');
      expect(resolved.text, isNot(contains('K19A/B/C/D')));
      expect(await settings.getCurrentCurriculum(), 'BIT_SE_K19D_K20A');

      final needsSpecialization = await controller.ask('Kỳ 5 tôi học gì?');
      expect(needsSpecialization.state, AskFptResponseState.clarification);
      expect(needsSpecialization.text, contains('chuyên ngành'));
      final semester = await controller.ask('Java chuyên sâu');
      expect(semester.text, contains('Học kỳ 5'));
      expect(semester.retrievedContext?['semester'], 5);
      expect(semester.retrievedContext?['specialization'], 'Java chuyên sâu');

      final restarted = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await restarted.initialize();
      final reused = await restarted.ask('Kỳ 6 tôi học gì?');
      expect(reused.state, AskFptResponseState.answered);
      expect(reused.text, isNot(contains('MSSV')));
    },
  );

  test('English and out-of-scope responses stay controlled', () async {
    final settingsDirectory = await Directory.systemTemp.createTemp(
      'language_settings_',
    );
    addTearDown(() => settingsDirectory.delete(recursive: true));
    final controller = AskFptController(
      repository,
      settings: AppSettings.forDirectory(settingsDirectory),
      groq: GroqAiService(apiKey: ''),
    );
    await controller.initialize();
    final english = await controller.ask('What is CEA201?');
    expect(english.text, isNot(contains('AI is unavailable')));
    final unrelated = await controller.ask('Messi hay Ronaldo?');
    expect(unrelated.state, AskFptResponseState.outOfScope);
    expect(unrelated.text, contains('FPT Knowledge'));
  });

  test(
    'explicit SE176711 resolution activates K17 and keeps saved K19',
    () async {
      final settingsDirectory = await Directory.systemTemp.createTemp(
        'context_priority_',
      );
      addTearDown(() => settingsDirectory.delete(recursive: true));
      final settings = AppSettings.forDirectory(settingsDirectory);
      await settings.setCurrentCurriculum('BIT_SE_K19D_K20A');
      final controller = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();

      await controller.ask('mã số sinh viên của tôi là SE176711');
      expect(await settings.getCurrentCurriculum(), 'BIT_SE_K17D_18A');
      expect(
        await settings.getCurriculumHistory(),
        containsAll(['BIT_SE_K17D_18A', 'BIT_SE_K19D_K20A']),
      );

      final answer = await controller.ask(
        'chương trình học của tôi gồm những môn nào',
      );
      expect(answer.retrievedContext?['curriculumCode'], 'BIT_SE_K17D_18A');
      expect(answer.text, contains('Software Engineering'));
      expect(answer.text, isNot(contains('BIT_SE_K17D_18A')));
      expect(answer.source, startsWith('BIT_SE_K17D_18A'));
      expect(answer.text, isNot(contains('AI đang không khả dụng')));

      await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');
      final switched = await controller.ask(
        'chương trình học của tôi gồm những môn nào',
      );
      expect(switched.retrievedContext?['curriculumCode'], 'BIT_SE_K19D_K20A');
      expect(
        await settings.getCurriculumHistory(),
        contains('BIT_SE_K17D_18A'),
      );
    },
  );

  test('removing My Curriculum state never removes database JSON', () async {
    final settingsDirectory = await Directory.systemTemp.createTemp(
      'curriculum_safety_',
    );
    addTearDown(() => settingsDirectory.delete(recursive: true));
    final settings = AppSettings.forDirectory(settingsDirectory);
    const code = 'BIT_SE_K19D_K20A';
    final sourceBefore = await repository.loadCurriculum(code);
    await settings.setCurrentCurriculum(code);
    await settings.removeCurriculum(code);

    expect(await settings.getCurrentCurriculum(), isNull);
    expect(await settings.getCurriculumHistory(), isNot(contains(code)));
    expect(await repository.containsCurriculum(code), isTrue);
    final sourceAfter = await repository.loadCurriculum(code);
    expect(sourceAfter?.subjects.length, sourceBefore?.subjects.length);
    expect(sourceAfter?.totalCredits, sourceBefore?.totalCredits);
  });

  test('personal subject-list questions use the active curriculum', () async {
    final settingsDirectory = await Directory.systemTemp.createTemp(
      'personal_curriculum_',
    );
    addTearDown(() => settingsDirectory.delete(recursive: true));
    final settings = AppSettings.forDirectory(settingsDirectory);
    final controller = AskFptController(
      repository,
      settings: settings,
      groq: GroqAiService(apiKey: ''),
    );
    await controller.initialize();
    await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');

    for (final question in [
      'cho tôi biết về những môn tôi sẽ học',
      'tôi sẽ học những môn nào',
      'chương trình của tôi gồm những môn nào',
    ]) {
      final answer = await controller.ask(question);
      expect(
        answer.retrievedContext?['curriculumCode'],
        'BIT_SE_K19D_K20A',
        reason: question,
      );
      expect(answer.retrievedContext?['semesters'], isA<List>());
      expect(answer.content.sections.map((section) => section.type).toSet(), {
        AskFptSectionType.subjectList,
      });
      expect(answer.text, contains('Software Engineering'));
      expect(answer.text, isNot(contains('BIT_SE_K19D_K20A')));
      expect(answer.text, isNot(contains('chưa xác định được môn học')));
      expect(answer.source, 'BIT_SE_K19D_K20A / Curriculum');
    }
  });

  test(
    'saved curricula never imply personal context without provenance',
    () async {
      final settingsDirectory = await Directory.systemTemp.createTemp(
        'no_assumption_',
      );
      addTearDown(() => settingsDirectory.delete(recursive: true));
      final settings = AppSettings.forDirectory(settingsDirectory);
      await settings.addCurriculum('BIT_SE_K17D_18A');
      await settings.setCurrentCurriculum('BIT_SE_K19D_K20A');
      final controller = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();

      final answer = await controller.ask(
        'chương trình học của tôi gồm những môn nào',
      );

      expect(controller.activeProvenance, ActiveContextProvenance.none);
      expect(answer.state, AskFptResponseState.needsStudentContext);
      expect(answer.text, contains('MSSV'));
      expect(answer.retrievedContext, isNull);
    },
  );

  test(
    'specialization clarification resumes and persists semester path',
    () async {
      final settingsDirectory = await Directory.systemTemp.createTemp(
        'specialization_resume_',
      );
      addTearDown(() => settingsDirectory.delete(recursive: true));
      final settings = AppSettings.forDirectory(settingsDirectory);
      final controller = AskFptController(
        repository,
        settings: settings,
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();
      await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');

      final clarification = await controller.ask(
        'Tôi đang học kỳ 8, tôi sẽ học những môn nào?',
      );
      expect(clarification.state, AskFptResponseState.clarification);
      expect(
        clarification.content.actions.map((action) => action.label),
        contains('Java chuyên sâu'),
      );

      final resumed = await controller.ask('Java chuyên sâu');
      final resumedCodes = (resumed.retrievedContext?['subjects'] as List)
          .whereType<Map>()
          .map((item) => item['code'])
          .toList();
      expect(resumedCodes, contains('MSS301'));
      expect(resumed.text, contains('Học kỳ 8'));
      expect(await settings.getCurrentSemester(), 8);
      expect(
        (await settings.getSpecialization('BIT_SE_K19D_K20A'))?.name,
        contains('SE_COM10.2'),
      );

      final reused = await controller.ask('Kỳ 7 tôi học gì?');
      expect(reused.state, isNot(AskFptResponseState.clarification));
      final reusedCodes = (reused.retrievedContext?['subjects'] as List)
          .whereType<Map>()
          .map((item) => item['code'])
          .toList();
      expect(reusedCodes, contains('SBA301'));
    },
  );

  test('note creation returns short My Notes and Obsidian handoff', () async {
    final settingsDirectory = await Directory.systemTemp.createTemp(
      'note_handoff_',
    );
    addTearDown(() => settingsDirectory.delete(recursive: true));
    final controller = AskFptController(
      repository,
      settings: AppSettings.forDirectory(settingsDirectory),
      groq: GroqAiService(apiKey: ''),
      exporter: _FakeNotesExporter(repository),
    );
    await controller.initialize();

    final response = await controller.ask('tôi cần note cho môn MSS');

    expect(response.state, AskFptResponseState.notesSuccess);
    expect(response.text, contains('MSS301'));
    expect(response.text.length, lessThan(700));
    expect(
      response.content.actions.map((action) => action.type),
      containsAll([
        AskFptActionType.viewMyNotes,
        AskFptActionType.openObsidian,
      ]),
    );
    expect(response.content.actions.map((action) => action.value).toSet(), {
      'subject:MSS301',
    });
  });

  test('chat restores after restart and New chat keeps profile', () async {
    final settingsDirectory = await Directory.systemTemp.createTemp(
      'chat_restore_',
    );
    addTearDown(() => settingsDirectory.delete(recursive: true));
    final settings = AppSettings.forDirectory(settingsDirectory);
    final controller = AskFptController(
      repository,
      settings: settings,
      groq: GroqAiService(apiKey: ''),
    );
    await controller.initialize();
    await controller.selectActiveCurriculum('BIT_SE_K19D_K20A');
    await settings.setCurrentSemester(8);
    controller.currentSemester = 8;
    await controller.recordUserMessage('CEA201 là môn gì?');
    final answer = await controller.ask('CEA201 là môn gì?');
    await controller.recordAssistantResponse(answer);

    final restarted = AskFptController(
      repository,
      settings: settings,
      groq: GroqAiService(apiKey: ''),
    );
    await restarted.initialize();
    expect(restarted.messages, hasLength(2));
    expect(restarted.messages.last.content?.title, contains('CEA201'));
    expect(restarted.currentSemester, 8);
    expect(
      restarted.activeProvenance,
      ActiveContextProvenance.explicitUseSelection,
    );

    await restarted.clearConversation();
    expect(restarted.messages, isEmpty);
    expect(await settings.getCurrentCurriculum(), 'BIT_SE_K19D_K20A');
    expect(await settings.getCurrentSemester(), 8);
    expect(
      await settings.getActiveContextProvenance(),
      ActiveContextProvenance.explicitUseSelection,
    );
  });

  testWidgets('structured answer renders clean UI and note action works', (
    tester,
  ) async {
    late Directory settingsDirectory;
    late AskFptController controller;
    await tester.runAsync(() async {
      settingsDirectory = await Directory.systemTemp.createTemp(
        'structured_ui_',
      );
      controller = AskFptController(
        repository,
        settings: AppSettings.forDirectory(settingsDirectory),
        groq: GroqAiService(apiKey: ''),
      );
      await controller.initialize();
      await controller.recordAssistantResponse(
        const AskFptResponse(
          text: 'Học kỳ 8',
          state: AskFptResponseState.notesSuccess,
          content: AskFptContent(
            title: 'Học kỳ 8',
            summary: 'Bạn sẽ học 1 môn.',
            sections: [
              AskFptSection(
                type: AskFptSectionType.subjectList,
                heading: 'Môn học',
                items: [
                  AskFptSectionItem(label: 'MSS301', value: 'Microservices'),
                ],
              ),
            ],
            actions: [
              AskFptAction(
                type: AskFptActionType.viewMyNotes,
                label: 'View in My Notes',
                value: 'subject:MSS301',
              ),
            ],
          ),
        ),
      );
    });
    addTearDown(() => settingsDirectory.delete(recursive: true));
    String? viewed;
    Widget buildAskScreen() => MaterialApp(
      home: Scaffold(
        body: AskFptScreen(
          controller: controller,
          onBrowseDatabase: () {},
          onOpenCurriculum: () {},
          onOpenNotes: () {},
          onProfileChanged: () {},
          onViewMyNotesItem: (value) => viewed = value,
          onOpenMyNotesItem: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(buildAskScreen());
    await tester.pump();
    expect(find.text('Học kỳ 8'), findsOneWidget);
    expect(find.text('MSS301'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('<br>'), findsNothing);
    expect(find.textContaining('---'), findsNothing);
    expect(find.textContaining('|'), findsNothing);
    await tester.tap(find.text('View in My Notes'));
    expect(viewed, 'subject:MSS301');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Database'))),
    );
    await tester.pumpWidget(buildAskScreen());
    expect(find.text('MSS301'), findsOneWidget);
  });

  test('Groq sends only supplied context and parses a valid answer', () async {
    String? sentBody;
    final service = GroqAiService(
      apiKey: 'test-only-key',
      transport: (uri, headers, body) async {
        sentBody = body;
        return const GroqHttpResponse(
          200,
          '{"choices":[{"message":{"content":"Câu trả lời"}}]}',
        );
      },
    );
    final answer = await service.answer(
      question: 'CEA201 là môn gì?',
      context: {'code': 'CEA201', 'description': 'Local only'},
      english: false,
    );
    expect(answer.text, 'Câu trả lời');
    expect(service.diagnostics.keyDetected, isTrue);
    expect(service.diagnostics.model, GroqAiService.defaultModel);
    expect(service.diagnostics.lastStatus, GroqRequestStatus.success);
    expect(sentBody, contains('CEA201'));
    expect(sentBody, isNot(contains('BIT_SE_K19B')));
    expect(jsonDecode(sentBody!)['model'], GroqAiService.defaultModel);
  });

  test('Groq parses machine-readable structured answers', () async {
    final structured = {
      'title': 'Học kỳ 8',
      'summary': 'Bạn sẽ học 1 môn.',
      'sections': [
        {
          'type': 'subject_list',
          'heading': 'Môn học',
          'items': [
            {'label': 'MSS301', 'value': 'Microservices'},
          ],
        },
      ],
    };
    final service = GroqAiService(
      apiKey: 'test-only-key',
      transport: (_, _, _) async => GroqHttpResponse(
        200,
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(structured)},
            },
          ],
        }),
      ),
    );

    final answer = await service.answer(
      question: 'Kỳ 8 học gì?',
      context: const {},
      english: false,
    );

    expect(answer.structured?['title'], 'Học kỳ 8');
    expect(answer.structured?['sections'], isA<List>());
  });

  test('plain-text fallback removes broken Markdown artifacts', () {
    final content = AskFptContent.fromPlainText(
      '**Assessment**\n| Type | Weight |\n| --- | --- |\n<br>\n- PE 30%',
    );
    final text = content.toPlainText();
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('<br>')));
    expect(text, isNot(contains('|')));
    expect(text, isNot(contains('---')));
    expect(text, contains('PE 30%'));
  });

  test('default Groq transport handles Vietnamese JSON as UTF-8', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? receivedBody;
    server.listen((request) async {
      receivedBody = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '{"choices":[{"message":{"content":"Đã trả lời"}}]}',
      );
      await request.response.close();
    });
    final service = GroqAiService(
      apiKey: 'test-only-key',
      endpoint: 'http://${server.address.address}:${server.port}/chat',
    );

    final answer = await service.answer(
      question: 'Tôi muốn biết về chương trình học của tôi',
      context: const {'curriculum': 'Chương trình Kỹ thuật phần mềm'},
      english: false,
    );

    expect(answer.text, 'Đã trả lời');
    expect(service.diagnostics.lastStatus, GroqRequestStatus.success);
    expect(receivedBody, contains('Tôi muốn biết'));
    expect(receivedBody, contains('Chương trình Kỹ thuật phần mềm'));
  });

  test('controller never sends the raw Student ID to Groq', () async {
    final settingsDirectory = await Directory.systemTemp.createTemp(
      'privacy_settings_',
    );
    addTearDown(() => settingsDirectory.delete(recursive: true));
    String? sentBody;
    final controller = AskFptController(
      repository,
      settings: AppSettings.forDirectory(settingsDirectory),
      groq: GroqAiService(
        apiKey: 'test-only-key',
        transport: (_, _, body) async {
          sentBody = body;
          return const GroqHttpResponse(
            200,
            '{"choices":[{"message":{"content":"Đã trả lời"}}]}',
          );
        },
      ),
    );
    await controller.initialize();
    await controller.ask('SE193911 CEA201 là môn gì?');
    expect(sentBody, isNotNull);
    expect(sentBody, isNot(contains('SE193911')));
    expect(sentBody, contains('[student profile resolved locally]'));
    expect(sentBody, contains('CEA201'));
  });

  test(
    'Groq handles missing key, 429, 5xx, timeout, and invalid JSON',
    () async {
      final missing = GroqAiService(apiKey: '');
      expect(
        (await missing.answer(
          question: 'q',
          context: const {},
          english: false,
        )).failure,
        GroqFailureKind.unavailable,
      );
      expect(missing.diagnostics.keyDetected, isFalse);
      expect(missing.diagnostics.lastStatus, GroqRequestStatus.missingKey);

      var rateCalls = 0;
      final rate = GroqAiService(
        apiKey: 'test',
        transport: (_, _, _) async {
          rateCalls++;
          return const GroqHttpResponse(429, '{}');
        },
      );
      expect(
        (await rate.answer(
          question: 'q',
          context: const {},
          english: false,
        )).failure,
        GroqFailureKind.rateLimited,
      );
      expect(rateCalls, 3);

      final server = GroqAiService(
        apiKey: 'test',
        transport: (_, _, _) async => const GroqHttpResponse(503, '{}'),
      );
      expect(
        (await server.answer(
          question: 'q',
          context: const {},
          english: false,
        )).failure,
        GroqFailureKind.server,
      );

      final timeout = GroqAiService(
        apiKey: 'test',
        timeout: const Duration(milliseconds: 1),
        transport: (_, _, _) => Completer<GroqHttpResponse>().future,
      );
      expect(
        (await timeout.answer(
          question: 'q',
          context: const {},
          english: false,
        )).failure,
        GroqFailureKind.timeout,
      );

      final invalid = GroqAiService(
        apiKey: 'test',
        transport: (_, _, _) async => const GroqHttpResponse(200, 'invalid'),
      );
      expect(
        (await invalid.answer(
          question: 'q',
          context: const {},
          english: false,
        )).failure,
        GroqFailureKind.invalidResponse,
      );

      final unauthorized = GroqAiService(
        apiKey: 'invalid',
        transport: (_, _, _) async => const GroqHttpResponse(401, '{}'),
      );
      expect(
        (await unauthorized.answer(
          question: 'q',
          context: const {},
          english: false,
        )).failure,
        GroqFailureKind.unauthorized,
      );
      expect(
        unauthorized.diagnostics.lastStatus,
        GroqRequestStatus.unauthorized,
      );

      final network = GroqAiService(
        apiKey: 'test',
        transport: (_, _, _) async => throw const SocketException('offline'),
      );
      expect(
        (await network.answer(
          question: 'q',
          context: const {},
          english: false,
        )).failure,
        GroqFailureKind.socket,
      );
      expect(network.diagnostics.lastStatus, GroqRequestStatus.socketError);
      expect(rate.diagnostics.lastStatus, GroqRequestStatus.rateLimited);
      expect(server.diagnostics.lastStatus, GroqRequestStatus.http5xx);
      expect(timeout.diagnostics.lastStatus, GroqRequestStatus.timeout);
      expect(invalid.diagnostics.lastStatus, GroqRequestStatus.parseError);

      final tls = GroqAiService(
        apiKey: 'test',
        transport: (_, _, _) async => throw HandshakeException('TLS failed'),
      );
      expect(
        (await tls.answer(
          question: 'q',
          context: const {},
          english: false,
        )).failure,
        GroqFailureKind.tls,
      );
      expect(tls.diagnostics.lastStatus, GroqRequestStatus.tlsError);

      final notFound = GroqAiService(
        apiKey: 'test',
        transport: (_, _, _) async => const GroqHttpResponse(404, '{}'),
      );
      await notFound.answer(question: 'q', context: const {}, english: false);
      expect(notFound.diagnostics.lastStatus, GroqRequestStatus.httpError);
      expect(notFound.diagnostics.endpointHost, 'api.groq.com');
    },
  );
}

class _FakeNotesExporter extends JsonMarkdownExportService {
  _FakeNotesExporter(super.repository);

  @override
  Future<MarkdownExportResult?> addSubjectToMyNotes(
    String subjectCode, {
    Directory? rootDirectory,
  }) async => const MarkdownExportResult(
    path: r'C:\FPT Knowledge\My Notes\Subjects\MSS301.md',
    exportedSubjects: 1,
  );
}
