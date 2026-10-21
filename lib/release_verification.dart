import 'dart:convert';
import 'dart:io';

import 'ai/ask_fpt_controller.dart';
import 'ai/groq_ai_service.dart';
import 'database/bundled_database_installer.dart';
import 'database/database_repository.dart';
import 'database/database_updater.dart';
import 'notes/json_markdown_export_service.dart';
import 'settings/app_settings.dart';

// Invoked explicitly by release QA; ordinary double-click startup is unchanged.
// Reports contain academic text and status only, never credentials or headers.
Future<int> verifyRelease({required bool online}) async {
  final profile = Platform.environment['APPDATA'];
  if (profile == null ||
      !File('$profile/.fpt-release-verification').existsSync()) {
    return 64; // Require an explicitly isolated test profile, never real user state.
  }
  final report = <String, dynamic>{
    'online': online,
    'osGroqKeyPresent': Platform.environment.containsKey('GROQ_API_KEY'),
  };
  var passed = false;
  try {
    final installer = BundledDatabaseInstaller();
    final directory = await installer.ensureInstalled();
    final repository = DatabaseRepository(directory);
    await repository.initialize();
    for (final code in ['CEA201', 'PRM393']) {
      if (await repository.loadSubject(code) == null ||
          (await repository.search(code)).isEmpty) {
        throw StateError('Required installed subject missing');
      }
    }
    final settings = AppSettings.forDirectory(
      Directory('$profile/verification-settings'),
    );
    final exporter = JsonMarkdownExportService(repository, settings: settings);
    final exported = await exporter.exportSubject(
      'CEA201',
      rootDirectory: Directory('$profile/verification-vault'),
    );
    final personal = File('$profile/verification-vault/personal-note.md');
    if (!await personal.exists()) {
      await personal.writeAsString('Personal release verification note');
    }
    await settings.setCurrentCurriculum('BIT_SE_K18D_19A');
    if (exported == null ||
        !await Directory(exported.path).exists() ||
        await settings.getCurrentCurriculum() != 'BIT_SE_K18D_19A' ||
        await personal.readAsString() != 'Personal release verification note') {
      throw StateError('Notes/profile verification failed');
    }
    report.addAll({
      'curriculumCount': repository.curriculumCount,
      'subjectCount': repository.subjectCount,
      'localSubjectSearch': true,
      'markdownExport': true,
      'personalNotesPreserved': true,
    });
    final groq = GroqAiService();
    final controller = AskFptController(
      repository,
      settings: settings,
      groq: groq,
    );
    try {
      await controller.initialize();
      final response = await controller.ask(
        'CEA201 là môn gì? Mô tả thật ngắn gọn bằng tiếng Việt.',
      );
      final diagnostics = groq.diagnostics;
      report.addAll({
        'groqHttpStatus': diagnostics.lastHttpStatus,
        'groqStatus': diagnostics.lastStatus.name,
        'groqAnswerSuccessCount': diagnostics.answerSuccessCount,
        'groqPlannerSuccessCount': diagnostics.plannerSuccessCount,
        'answerState': response.state.name,
        'academicAnswer': response.text.substring(
          0,
          response.text.length > 400 ? 400 : response.text.length,
        ),
      });
      if (online) {
        passed =
            diagnostics.lastHttpStatus == 200 &&
            diagnostics.answerSuccessCount > 0 &&
            response.text.trim().isNotEmpty;
        final updates = DatabaseUpdater(directory);
        try {
          await updates.check(force: true);
          report['dataUpdateStatus'] = updates.status.name;
          await updates.check(force: true);
          final afterConditionalCheck = updates.completedRequests;
          await updates.check();
          report['dataUpdateHttpRequests'] = updates.completedRequests;
          report['dataUpdateBodyBytes'] = updates.downloadedBytes;
          report['dataUpdateTtlSkippedRequest'] =
              updates.completedRequests == afterConditionalCheck;
        } finally {
          updates.dispose();
        }
      } else {
        passed =
            diagnostics.answerSuccessCount == 0 &&
            response.text.trim().isNotEmpty;
      }
    } finally {
      controller.dispose();
    }
    report['passed'] = passed;
  } catch (_) {
    // Avoid serializing exceptions that could carry request configuration.
    report['passed'] = false;
    report['error'] =
        'Release verification failed; inspect non-secret status fields.';
  }
  await File('$profile/release-verification.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  return passed ? 0 : 1;
}
