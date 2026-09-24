export 'ask_fpt_models.dart';

import 'package:flutter/foundation.dart';

import '../database/database_repository.dart';
import '../flm/flm_combo_service.dart';
import '../notes/json_markdown_export_service.dart';
import '../search/curriculum_search.dart';
import '../settings/app_settings.dart';
import 'ask_fpt_models.dart';
import 'ask_fpt_intent_resolver.dart';
import 'ask_fpt_planner.dart';
import 'groq_ai_service.dart';
import 'student_context.dart';
import 'student_profile_resolver.dart';

class AskFptController extends ChangeNotifier {
  final DatabaseRepository repository;
  final AppSettings settings;
  final GroqAiService groq;
  late final AskFptPlanner planner;
  final AskFptIntentResolver intentResolver;
  final StudentProfileResolver profileResolver;
  final JsonMarkdownExportService exporter;
  final StudentContext studentContext = StudentContext();

  String? recentSubject;
  AskFptIntent? recentIntent;
  ResolvedStudentProfile? resolvedProfile;
  final List<AskFptChatMessage> messages = [];
  AskFptPlan? lastPlan;

  String? get recentCurriculum => studentContext.curriculum;
  set recentCurriculum(String? value) => studentContext.curriculum = value;
  int? get currentSemester => studentContext.currentSemester;
  set currentSemester(int? value) => studentContext.currentSemester = value;
  ActiveContextProvenance get activeProvenance =>
      studentContext.curriculumProvenance;
  set activeProvenance(ActiveContextProvenance value) =>
      studentContext.curriculumProvenance = value;
  String? get _pendingQuestion => studentContext.pendingQuestion;
  set _pendingQuestion(String? value) => studentContext.pendingQuestion = value;
  String? get _pendingSpecializationCurriculum =>
      studentContext.pendingSpecializationCurriculum;
  set _pendingSpecializationCurriculum(String? value) =>
      studentContext.pendingSpecializationCurriculum = value;

  AskFptController(
    this.repository, {
    AppSettings? settings,
    GroqAiService? groq,
    AskFptPlanner? planner,
    AskFptIntentResolver? intentResolver,
    StudentProfileResolver? profileResolver,
    JsonMarkdownExportService? exporter,
  }) : settings = settings ?? AppSettings.instance,
       groq = groq ?? GroqAiService(),
       intentResolver = intentResolver ?? const AskFptIntentResolver(),
       profileResolver = profileResolver ?? StudentProfileResolver(repository),
       exporter =
           exporter ??
           JsonMarkdownExportService(
             repository,
             settings: settings ?? AppSettings.instance,
           ) {
    this.planner = planner ?? GroqAskFptPlanner(this.groq);
  }

  Future<void> initialize() async {
    currentSemester = await settings.getCurrentSemester();
    activeProvenance = await settings.getActiveContextProvenance();
    final saved = await settings.getResolvedStudentProfile();
    if (saved != null) {
      final profile = ResolvedStudentProfile.fromJson(saved);
      if (profile.primaryCurriculum.isNotEmpty &&
          await repository.containsCurriculum(profile.primaryCurriculum)) {
        resolvedProfile = profile;
      }
    }
    final current = await settings.getCurrentCurriculum();
    if (activeProvenance == ActiveContextProvenance.studentIdResolved &&
        resolvedProfile != null) {
      activeProvenance = ActiveContextProvenance.restoredExplicitProfile;
      await settings.setActiveContextProvenance(activeProvenance);
    }
    if (activeProvenance != ActiveContextProvenance.none &&
        current != null &&
        await repository.containsCurriculum(current)) {
      studentContext.changeCurriculum(
        current,
        activeProvenance,
        resolvedMajor: resolvedProfile?.majorPrefix,
        resolvedCohort: resolvedProfile?.cohort,
      );
      await _restoreSpecializationFor(current, markRestored: true);
    } else if (activeProvenance != ActiveContextProvenance.none) {
      activeProvenance = ActiveContextProvenance.none;
      await settings.setActiveContextProvenance(activeProvenance);
    }
    await _restoreSession();
  }

  Future<void> selectActiveCurriculum(String curriculumCode) async {
    final code = curriculumCode.trim().toUpperCase();
    if (!await repository.containsCurriculum(code)) {
      throw StateError('Curriculum $code is unavailable locally.');
    }
    final changed = recentCurriculum != code;
    studentContext.changeCurriculum(
      code,
      ActiveContextProvenance.explicitUseSelection,
    );
    if (changed) {
      currentSemester = null;
      await settings.setCurrentSemester(null);
    }
    await settings.setCurrentCurriculum(code);
    await settings.setActiveContextProvenance(activeProvenance);
    await _restoreSpecializationFor(code);
  }

  Future<void> adoptActiveCurriculum(String? curriculumCode) async {
    final code = curriculumCode?.trim().toUpperCase();
    if (code == null || code.isEmpty) {
      studentContext.changeCurriculum(null, ActiveContextProvenance.none);
      await settings.setActiveContextProvenance(activeProvenance);
    } else if (activeProvenance != ActiveContextProvenance.none) {
      final changed = recentCurriculum != code;
      final profile = resolvedProfile;
      studentContext.changeCurriculum(
        code,
        activeProvenance,
        resolvedMajor: profile?.primaryCurriculum == code
            ? profile?.majorPrefix
            : null,
        resolvedCohort: profile?.primaryCurriculum == code
            ? profile?.cohort
            : null,
      );
      if (changed) {
        currentSemester = null;
        await settings.setCurrentSemester(null);
      }
      await _restoreSpecializationFor(code);
    }
  }

  Future<void> recordUserMessage(String text) async {
    messages.add(AskFptChatMessage.user(text.trim()));
    notifyListeners();
    await _persistSession();
  }

  Future<void> recordAssistantResponse(AskFptResponse response) async {
    messages.add(AskFptChatMessage.assistant(response));
    notifyListeners();
    await _persistSession();
  }

  Future<void> clearConversation() async {
    messages.clear();
    recentSubject = null;
    recentIntent = null;
    _pendingQuestion = null;
    _pendingSpecializationCurriculum = null;
    notifyListeners();
    await settings.clearAskFptSession();
  }

  Future<AskFptResponse> ask(String rawQuestion) async {
    final question = rawQuestion.trim();
    if (question.isEmpty) {
      return const AskFptResponse(
        text: 'Bạn hãy nhập câu hỏi về chương trình hoặc môn học FPT.',
        state: AskFptResponseState.databaseUnavailable,
      );
    }

    if (_isSpecializationReset(question)) {
      return _clearSpecialization(question);
    }

    if (_pendingQuestion != null && _pendingSpecializationCurriculum != null) {
      final curriculum = _pendingSpecializationCurriculum!;
      final selected = await _matchSpecialization(curriculum, question);
      if (selected != null) {
        final pending = _pendingQuestion!;
        await _setSpecialization(curriculum, selected);
        _pendingQuestion = null;
        _pendingSpecializationCurriculum = null;
        await _persistSession();
        return ask(pending);
      }
      return _specializationClarification(
        curriculum,
        _isEnglish(question),
        keepPending: true,
      );
    }

    var providerQuestion = question;
    final student = profileResolver.parse(question);
    if (student != null) {
      providerQuestion = _redactStudentId(question);
      final profile = await profileResolver.resolve(student);
      if (profile == null) {
        return AskFptResponse(
          text: _isEnglish(question)
              ? 'I could not match that student ID to a curriculum in the local database.'
              : 'Mình chưa tìm thấy chương trình phù hợp với MSSV này trong dữ liệu hiện tại.',
          state: AskFptResponseState.databaseUnavailable,
        );
      }
      resolvedProfile = profile;
      final changed = recentCurriculum != profile.primaryCurriculum;
      studentContext.changeCurriculum(
        profile.primaryCurriculum,
        ActiveContextProvenance.studentIdResolved,
        resolvedMajor: profile.majorPrefix,
        resolvedCohort: profile.cohort,
      );
      if (changed) {
        currentSemester = null;
        await settings.setCurrentSemester(null);
      }
      await settings.setResolvedStudentProfile(profile.toJson());
      await settings.setCurrentCurriculum(profile.primaryCurriculum);
      await settings.setActiveContextProvenance(activeProvenance);
      await _restoreSpecializationFor(profile.primaryCurriculum);
      if (!_containsAcademicQuestionBesidesId(question)) {
        final friendly = await _friendlyCurriculumLabel(
          profile.primaryCurriculum,
        );
        return AskFptResponse(
          text: _isEnglish(question)
              ? 'I identified your program as $friendly. You can ask a curriculum question now.'
              : 'Mình đã xác định chương trình của bạn là $friendly. Bạn có thể hỏi tiếp về học kỳ hoặc môn học.',
          state: AskFptResponseState.answered,
          source: '${profile.primaryCurriculum} / Resolved profile',
          content: AskFptContent(
            title: friendly,
            summary: _isEnglish(question)
                ? 'Your student profile was resolved locally.'
                : 'Hồ sơ sinh viên đã được xác định bằng dữ liệu cục bộ.',
          ),
        );
      }
    }

    final specializationCommand = await _handleSpecializationCommand(question);
    if (specializationCommand != null) return specializationCommand;

    final noteAction = await _handleDeterministicNoteAction(question);
    if (noteAction != null) return noteAction;

    final namedSpecialization = await _handleNamedSpecializationQuery(question);
    if (namedSpecialization != null) return namedSpecialization;

    if (_isAmbiguousMajorStatement(question)) {
      const message =
          'Bạn đang nói về ngành Software Engineering, một môn học, hay chuyên ngành?';
      return const AskFptResponse(
        text: message,
        state: AskFptResponseState.clarification,
        content: AskFptContent(summary: message),
      );
    }

    var route = intentResolver.resolve(question);
    lastPlan = null;
    if (_shouldUsePlanner(question, route)) {
      final active = await _activeCurriculum();
      final selected = active == null ? null : _selectedSpecialization(active);
      final planned = await planner.plan(
        question: providerQuestion,
        knownContext: {
          'hasActiveCurriculum': active != null,
          'hasCurrentSemester': currentSemester != null,
          'hasExplicitSpecialization': selected != null,
        },
        english: route.english,
      );
      if (planned != null) {
        lastPlan = planned;
        if (planned.clarificationNeeded || planned.intent == 'unclear') {
          final text = planned.clarificationQuestion?.trim();
          return AskFptResponse(
            text: text?.isNotEmpty == true
                ? text!
                : (route.english
                      ? 'Could you clarify which academic information you want?'
                      : 'Bạn muốn xem các môn trong chương trình, các môn ngoài chuyên ngành hay các môn tự chọn?'),
            state: AskFptResponseState.clarification,
            content: AskFptContent(
              title: route.english ? 'Clarification needed' : 'Cần làm rõ',
              summary: text?.isNotEmpty == true
                  ? text!
                  : 'Bạn muốn xem các môn trong chương trình, các môn ngoài chuyên ngành hay các môn tự chọn?',
            ),
          );
        }
        route = _routeFromPlan(planned, route);
      }
    }
    recentIntent = route.intent;
    if (route.statedCurrentSemester != null) {
      currentSemester = route.statedCurrentSemester;
      await settings.setCurrentSemester(currentSemester);
    }

    if (route.intent == AskFptIntent.outOfScope) {
      return AskFptResponse(
        text: route.english
            ? 'I only support study information based on FPT Knowledge data.'
            : 'Mình chỉ hỗ trợ thông tin học tập dựa trên dữ liệu FPT Knowledge.',
        state: AskFptResponseState.outOfScope,
      );
    }

    if (_isSubjectIntent(route.intent)) {
      final resolution = await _resolveSubject(question);
      if (resolution.ambiguous.isNotEmpty) {
        return AskFptResponse(
          text: route.english
              ? 'Which subject do you mean: ${resolution.ambiguous.join(', ')}?'
              : 'Bạn muốn hỏi môn nào: ${resolution.ambiguous.join(', ')}?',
          state: AskFptResponseState.clarification,
        );
      }
      final code = resolution.code;
      if (code == null) {
        return AskFptResponse(
          text: route.english
              ? 'I could not identify a subject in the local database.'
              : 'Mình chưa xác định được môn học trong dữ liệu hiện tại.',
          state: AskFptResponseState.databaseUnavailable,
        );
      }
      recentSubject = code;
      if (route.intent == AskFptIntent.notesAddSubject) {
        return _exportSubject(code, route.english);
      }
      final context = await _subjectContext(code, route.intent);
      if (context == null) {
        return AskFptResponse(
          text: route.english
              ? 'That subject is not available in the current database.'
              : 'Môn này chưa có trong dữ liệu FPT Knowledge hiện tại.',
          state: AskFptResponseState.databaseUnavailable,
        );
      }
      return _answerWithContext(
        question: providerQuestion,
        context: context,
        local: _localSubjectContent(code, context, route.intent, route.english),
        source: '$code / ${_sourcePart(route.intent)}',
        english: route.english,
      );
    }

    final curriculumCode = await _activeCurriculum();
    if (curriculumCode == null) {
      return AskFptResponse(
        text: route.english
            ? 'I do not know your curriculum yet. Send your student ID, for example SE193911, so I can identify it.'
            : 'Mình chưa biết chương trình của bạn. Bạn gửi MSSV, ví dụ SE193911, để mình xác định chương trình nhé.',
        state: AskFptResponseState.needsStudentContext,
        content: AskFptContent(
          title: route.english ? 'Student context needed' : 'Cần MSSV',
          summary: route.english
              ? 'Send your student ID, for example SE193911.'
              : 'Mình chưa biết chương trình của bạn. Bạn gửi MSSV, ví dụ SE193911, để mình xác định chương trình nhé.',
        ),
      );
    }
    recentCurriculum = curriculumCode;
    if (route.intent == AskFptIntent.notesAddCurriculum) {
      return _exportCurriculum(curriculumCode, route.english);
    }
    var semester = route.semester;
    if (route.intent == AskFptIntent.futureSemester) {
      semester = route.semester != null
          ? route.semester! + 1
          : (currentSemester == null ? null : currentSemester! + 1);
      if (semester == null) {
        return AskFptResponse(
          text: route.english
              ? 'Tell me your current semester first, for example “I am in semester 3”.'
              : 'Bạn cho mình biết học kỳ hiện tại trước, ví dụ “Mình đang học kỳ 3”.',
          state: AskFptResponseState.needsStudentContext,
        );
      }
    }
    if (route.intent == AskFptIntent.notesAddSemester) {
      if (semester == null) {
        return AskFptResponse(
          text: route.english
              ? 'Which semester should I export?'
              : 'Bạn muốn xuất học kỳ mấy?',
          state: AskFptResponseState.clarification,
        );
      }
      return _exportSemester(curriculumCode, semester, route.english);
    }
    if (semester != null &&
        await _requiresSpecialization(curriculumCode, semester)) {
      final selected = _selectedSpecialization(curriculumCode);
      if (selected == null) {
        _pendingQuestion = question;
        _pendingSpecializationCurriculum = curriculumCode;
        await _persistSession();
        return _semesterWithUnknownSpecialization(
          curriculumCode,
          semester,
          route.english,
        );
      }
    } else if (route.intent == AskFptIntent.compareSpecializationAndCore) {
      final selected = _selectedSpecialization(curriculumCode);
      if (selected == null) {
        _pendingQuestion = question;
        _pendingSpecializationCurriculum = curriculumCode;
        await _persistSession();
        return _specializationClarification(curriculumCode, route.english);
      }
    }
    final context = await _curriculumContext(
      curriculumCode,
      route.intent,
      semester,
    );
    if (context == null) {
      return AskFptResponse(
        text: route.english
            ? 'The requested curriculum data is unavailable.'
            : 'Dữ liệu chương trình cần thiết hiện chưa có.',
        state: AskFptResponseState.databaseUnavailable,
      );
    }
    final source =
        '$curriculumCode / ${route.intent == AskFptIntent.personalCurriculumSubjects
            ? 'Curriculum'
            : semester == null
            ? 'Overview'
            : 'Semester $semester'}';
    final local = _localCurriculumContent(context, route.english);
    if (_isLargeDeterministicIntent(route.intent)) {
      return _localAnswer(context: context, content: local, source: source);
    }
    return _answerWithContext(
      question: providerQuestion,
      context: context,
      local: local,
      source: source,
      english: route.english,
    );
  }

  static bool _isLargeDeterministicIntent(AskFptIntent intent) => {
    AskFptIntent.personalCurriculumSubjects,
    AskFptIntent.semesterSubjects,
    AskFptIntent.futureSemester,
    AskFptIntent.specializationOverview,
    AskFptIntent.compareSpecializationAndCore,
  }.contains(intent);

  AskFptResponse _localAnswer({
    required Map<String, dynamic> context,
    required AskFptContent content,
    required String source,
    AskFptResponseState state = AskFptResponseState.answered,
  }) => AskFptResponse(
    text: content.toPlainText(),
    state: state,
    source: source,
    retrievedContext: context,
    content: content,
  );

  Future<AskFptResponse> _semesterWithUnknownSpecialization(
    String curriculum,
    int semester,
    bool english,
  ) async {
    final context = await _curriculumContext(
      curriculum,
      AskFptIntent.semesterSubjects,
      semester,
    );
    if (context == null) {
      return AskFptResponse(
        text: english
            ? 'The requested curriculum data is unavailable.'
            : 'Dữ liệu chương trình cần thiết hiện chưa có.',
        state: AskFptResponseState.databaseUnavailable,
      );
    }
    final choices = await repository.loadProfessionalSpecializations(
      curriculum,
    );
    final startSemesters = choices
        .expand((choice) => choice.subjects)
        .map((subject) => subject.semester)
        .where((value) => value > 0)
        .toList();
    final startSemester = startSemesters.isEmpty
        ? null
        : (startSemesters..sort()).first;
    context['specializationMissing'] = true;
    if (startSemester != null) {
      context['specializationStartSemester'] = startSemester;
    }
    final base = _localCurriculumContent(context, english);
    final content = AskFptContent(
      title: base.title,
      summary: base.summary,
      sections: [
        ...base.sections,
        AskFptSection(
          type: AskFptSectionType.info,
          heading: english
              ? 'Specialization subjects not included'
              : 'Chưa bao gồm môn chuyên ngành',
          items: [
            AskFptSectionItem(
              label: '',
              value: english
                  ? 'The subjects above are the known core subjects. Specialization subjects are not included because your specialization is unknown.'
                  : 'Danh sách trên là các môn chung đã biết và chưa bao gồm các môn chuyên ngành vì mình chưa biết chuyên ngành bạn đã chọn.',
            ),
            if (startSemester != null)
              AskFptSectionItem(
                label: '',
                value: english
                    ? 'In this curriculum, specialization subjects begin in semester $startSemester and are added to their corresponding semesters.'
                    : 'Theo dữ liệu chương trình này, môn chuyên ngành bắt đầu từ học kỳ $startSemester và được bổ sung vào các học kỳ tương ứng.',
              ),
            AskFptSectionItem(
              label: '',
              value: english
                  ? 'Which professional specialization are you following?'
                  : 'Bạn đang theo chuyên ngành nào?',
            ),
          ],
        ),
      ],
      actions: [
        for (final choice in choices)
          AskFptAction(
            type: AskFptActionType.selectSpecialization,
            label: _friendlySpecializationName(choice),
            value: english
                ? 'my specialization is ${_friendlySpecializationName(choice)}'
                : 'chuyên ngành của tôi là ${_friendlySpecializationName(choice)}',
          ),
      ],
    );
    return _localAnswer(
      context: context,
      content: content,
      source: '$curriculum / Semester $semester',
      state: AskFptResponseState.clarification,
    );
  }

  Future<AskFptResponse> _answerWithContext({
    required String question,
    required Map<String, dynamic> context,
    required AskFptContent local,
    required String source,
    required bool english,
  }) async {
    final result = await groq.answer(
      question: question,
      context: context,
      english: english,
    );
    if (result.isSuccess) {
      final parsed = result.structured == null
          ? AskFptContent.fromPlainText(result.text!)
          : AskFptContent.fromJson(result.structured!);
      final content = parsed.toPlainText().isEmpty
          ? local
          : AskFptContent(
              title: parsed.title,
              summary: parsed.summary,
              sections: parsed.sections,
            );
      return AskFptResponse(
        text: content.toPlainText(),
        state: AskFptResponseState.answered,
        source: source,
        retrievedContext: context,
        content: content,
      );
    }
    if (result.failure == GroqFailureKind.invalidResponse) {
      final message = english
          ? 'I could not format this answer safely. Please try a shorter question.'
          : 'Mình chưa thể trình bày câu trả lời này đúng định dạng. Hãy thử hỏi lại ngắn hơn.';
      return AskFptResponse(
        text: message,
        state: AskFptResponseState.apiError,
        source: source,
        retrievedContext: context,
        content: AskFptContent(summary: message),
      );
    }
    final state = switch (result.failure) {
      GroqFailureKind.rateLimited => AskFptResponseState.rateLimited,
      GroqFailureKind.unauthorized => AskFptResponseState.apiError,
      GroqFailureKind.server ||
      GroqFailureKind.invalidResponse => AskFptResponseState.apiError,
      _ => AskFptResponseState.offline,
    };
    return AskFptResponse(
      text: local.toPlainText(),
      state: state,
      source: source,
      retrievedContext: context,
      content: local,
    );
  }

  bool _shouldUsePlanner(String question, AskFptIntentResult route) {
    final normalized = normalizeCurriculumSearchText(question);
    if ({
      AskFptIntent.personalCurriculumSubjects,
      AskFptIntent.curriculumOverview,
      AskFptIntent.semesterSubjects,
      AskFptIntent.futureSemester,
    }.contains(route.intent)) {
      return false;
    }
    if (RegExp(r'\b[A-Za-z]{2,6}\d{2,4}[A-Za-z]?\b').hasMatch(question)) {
      return false;
    }
    if (RegExp(
      r'\b(ghi chu|note|notes|obsidian|markdown|xuat|export)\b',
    ).hasMatch(normalized)) {
      return false;
    }
    if (_isSpecializationQuery(normalized) ||
        _isSpecializationList(normalized) ||
        _isBareSpecializationChange(normalized) ||
        _isSpecializationReset(question) ||
        RegExp(
          r'\b(toi hoc|minh hoc|cua toi la|cua minh la|doi sang|change to|switch to|khong phai)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(?:hoc ky|ky|semester|sem)\s*\d{1,2}\b',
        ).hasMatch(normalized)) {
      return false;
    }
    return true;
  }

  AskFptIntentResult _routeFromPlan(
    AskFptPlan plan,
    AskFptIntentResult fallback,
  ) {
    final intent = switch (plan.intent) {
      'subject_overview' => AskFptIntent.subjectOverview,
      'subject_assessment' => AskFptIntent.subjectAssessment,
      'subject_prerequisite' => AskFptIntent.subjectPrerequisite,
      'subject_materials' => AskFptIntent.subjectMaterials,
      'subject_outcomes' => AskFptIntent.subjectOutcomes,
      'subject_credits' => AskFptIntent.subjectCredits,
      'semester_subjects' => AskFptIntent.semesterSubjects,
      'curriculum_overview' => AskFptIntent.curriculumOverview,
      'personal_curriculum_subjects' => AskFptIntent.personalCurriculumSubjects,
      'list_specializations' => AskFptIntent.specializationOverview,
      'compare_specialization_and_core' =>
        AskFptIntent.compareSpecializationAndCore,
      _ when plan.domain == 'other' => AskFptIntent.outOfScope,
      _ => fallback.intent,
    };
    return AskFptIntentResult(
      intent: intent,
      personal:
          plan.requiresCurriculum ||
          plan.requiresSpecialization ||
          fallback.personal,
      english: fallback.english,
      semester: plan.semester ?? fallback.semester,
      statedCurrentSemester: fallback.statedCurrentSemester,
    );
  }

  Future<AskFptResponse?> _handleDeterministicNoteAction(
    String question,
  ) async {
    final normalized = normalizeCurriculumSearchText(question);
    if (!RegExp(r'\b(note|notes|my notes|ghi chu)\b').hasMatch(normalized)) {
      return null;
    }
    final asksForAction = RegExp(
      r'\b(cho|tao|them|luu|can|mo|add|create|save|open|need)\b',
    ).hasMatch(normalized);
    final referencesSubject = RegExp(
      r'\b(mon|subject|course)\b|\b[A-Za-z]{2,6}\d{0,4}[A-Za-z]?\b',
    ).hasMatch(question);
    if (!asksForAction && !referencesSubject) return null;
    final english = _isEnglish(question);
    final resolution = await _resolveSubject(question);
    if (resolution.ambiguous.isNotEmpty) {
      return AskFptResponse(
        text: english
            ? 'Which subject note do you mean: ${resolution.ambiguous.join(', ')}?'
            : 'Bạn muốn tạo ghi chú cho môn nào: ${resolution.ambiguous.join(', ')}?',
        state: AskFptResponseState.clarification,
      );
    }
    final code = resolution.code;
    if (code == null) {
      return AskFptResponse(
        text: english
            ? 'I could not identify the subject for this note action.'
            : 'Mình chưa xác định được môn học để tạo ghi chú.',
        state: AskFptResponseState.databaseUnavailable,
      );
    }
    recentSubject = code;
    return _exportSubject(code, english);
  }

  Future<AskFptResponse?> _handleNamedSpecializationQuery(
    String question,
  ) async {
    final normalized = normalizeCurriculumSearchText(question);
    if (!RegExp(r'\b(mon|subjects|courses)\b').hasMatch(normalized)) {
      return null;
    }
    final curriculum = await _activeCurriculum();
    if (curriculum == null) return null;
    final selected = await _matchSpecialization(curriculum, question);
    if (selected == null) return null;
    final english = _isEnglish(question);
    final name = _friendlySpecializationName(selected);
    final context = <String, dynamic>{
      'specialization': name,
      'subjects': [
        for (final subject in selected.subjects)
          {
            'code': subject.code,
            'name': subject.name,
            'semester': subject.semester,
          },
      ],
    };
    final content = AskFptContent(
      title: name,
      summary: english
          ? '${selected.subjects.length} professional specialization subjects.'
          : '${selected.subjects.length} môn chuyên ngành.',
      sections: [
        AskFptSection(
          type: AskFptSectionType.subjectList,
          heading: english ? 'Subjects' : 'Môn chuyên ngành',
          items: _subjectItems(context['subjects'], english: english),
        ),
      ],
    );
    return _localAnswer(
      context: context,
      content: content,
      source: '$curriculum / $name',
    );
  }

  Future<AskFptResponse?> _handleSpecializationCommand(String question) async {
    final normalized = normalizeCurriculumSearchText(question);
    final explicitCommand =
        _isSpecializationQuery(normalized) ||
        _isSpecializationExplanation(normalized) ||
        _isSpecializationList(normalized) ||
        _isBareSpecializationChange(normalized) ||
        _isSpecializationReset(question) ||
        RegExp(
          r'\b(chuyen nganh|specialization|combo)\b.*\b(la|chon|doi|change|switch|use)\b|\b(doi|change|switch|use)\b.*\b(chuyen nganh|specialization|combo)\b|\bkhong phai\b',
        ).hasMatch(normalized) ||
        RegExp(r'\b(chuyen|doi|change|switch)\s+sang\b').hasMatch(normalized);
    final possibleDirectSelection =
        RegExp(r'^(toi|minh|i)\s+(hoc|study|use)\b').hasMatch(normalized) &&
        !RegExp(
          r'\b(gi|ky|hoc ky|mon|semester|subject|course|software engineering)\b|^(toi|minh|i)\s+(hoc|study)\s+(se|ai|ia|gd)$',
        ).hasMatch(normalized);
    if (!explicitCommand && !possibleDirectSelection) return null;
    final english = _isEnglish(question);
    final curriculum = await _activeCurriculum();
    if (curriculum == null) {
      return AskFptResponse(
        text: english
            ? 'I do not know your curriculum yet. Send your student ID first.'
            : 'Mình chưa biết chương trình của bạn. Bạn gửi MSSV trước nhé.',
        state: AskFptResponseState.needsStudentContext,
      );
    }
    if (_isSpecializationExplanation(normalized)) {
      return _specializationExplanation(curriculum, english);
    }
    if (_isSpecializationQuery(normalized)) {
      final selected = _selectedSpecialization(curriculum);
      if (selected == null) {
        return _specializationClarification(curriculum, english);
      }
      final name = _friendlySpecializationName(selected);
      final content = AskFptContent(
        title: english ? 'Your specialization' : 'Chuyên ngành của bạn',
        summary: name,
        actions: [
          AskFptAction(
            type: AskFptActionType.changeSpecialization,
            label: english ? 'Change specialization' : 'Đổi chuyên ngành',
            value: english ? 'change specialization' : 'đổi chuyên ngành',
          ),
          AskFptAction(
            type: AskFptActionType.clearSpecialization,
            label: english ? 'Clear specialization' : 'Bỏ chuyên ngành',
            value: english
                ? 'clear current specialization'
                : 'bỏ chuyên ngành hiện tại',
          ),
        ],
      );
      return AskFptResponse(
        text: content.toPlainText(),
        state: AskFptResponseState.answered,
        source: '$curriculum / Explicit specialization profile',
        content: content,
      );
    }
    if (_isSpecializationList(normalized) ||
        _isBareSpecializationChange(normalized)) {
      return _specializationClarification(curriculum, english);
    }
    if (normalized.contains('khong phai') &&
        !RegExp(
          r'\b(toi hoc|minh hoc|ma la|chuyen sang|doi sang|switch to|change to)\b',
        ).hasMatch(normalized)) {
      await _clearSelectedSpecialization(curriculum);
      return _specializationClarification(curriculum, english);
    }
    final selected = await _matchSpecialization(curriculum, question);
    if (selected == null) {
      return _specializationClarification(
        curriculum,
        english,
        invalidSelection: true,
      );
    }
    await _setSpecialization(curriculum, selected);
    final name = _friendlySpecializationName(selected);
    final content = AskFptContent(
      title: english ? 'Specialization updated' : 'Đã cập nhật chuyên ngành',
      summary: name,
      actions: [
        AskFptAction(
          type: AskFptActionType.changeSpecialization,
          label: english ? 'Change specialization' : 'Đổi chuyên ngành',
          value: english ? 'change specialization' : 'đổi chuyên ngành',
        ),
        AskFptAction(
          type: AskFptActionType.clearSpecialization,
          label: english ? 'Clear specialization' : 'Bỏ chuyên ngành',
          value: english
              ? 'clear current specialization'
              : 'bỏ chuyên ngành hiện tại',
        ),
      ],
    );
    return AskFptResponse(
      text: content.toPlainText(),
      state: AskFptResponseState.answered,
      source: '$curriculum / Explicit specialization profile',
      content: content,
    );
  }

  Future<AskFptResponse> _clearSpecialization(String question) async {
    final english = _isEnglish(question);
    final curriculum = await _activeCurriculum();
    if (curriculum == null) {
      return AskFptResponse(
        text: english
            ? 'There is no active curriculum specialization to clear.'
            : 'Hiện chưa có chuyên ngành nào để xóa.',
        state: AskFptResponseState.needsStudentContext,
      );
    }
    await _clearSelectedSpecialization(curriculum);
    _pendingQuestion = null;
    _pendingSpecializationCurriculum = null;
    await _persistSession();
    final message = english
        ? 'Your specialization is unknown again.'
        : 'Đã bỏ chuyên ngành hiện tại. Chuyên ngành của bạn đang ở trạng thái chưa xác định.';
    return AskFptResponse(
      text: message,
      state: AskFptResponseState.answered,
      content: AskFptContent(summary: message),
    );
  }

  Future<AskFptResponse> _specializationExplanation(
    String curriculum,
    bool english,
  ) async {
    final choices = await repository.loadProfessionalSpecializations(
      curriculum,
    );
    final semesters =
        choices
            .expand((choice) => choice.subjects)
            .map((subject) => subject.semester)
            .where((value) => value > 0)
            .toList()
          ..sort();
    final start = semesters.isEmpty ? null : semesters.first;
    final content = AskFptContent(
      title: english ? 'Professional specialization' : 'Chuyên ngành',
      summary: english
          ? 'A professional specialization is the curriculum track whose subjects fill the major-specific combination slots.'
          : 'Chuyên ngành là hướng học chuyên môn có các môn được điền vào những vị trí combo chuyên ngành của chương trình.',
      sections: [
        AskFptSection(
          type: AskFptSectionType.info,
          items: [
            if (start != null)
              AskFptSectionItem(
                label: english
                    ? 'Starts in local data'
                    : 'Bắt đầu theo dữ liệu',
                value: english ? 'Semester $start' : 'Học kỳ $start',
              )
            else
              AskFptSectionItem(
                label: '',
                value: english
                    ? 'The current database does not specify the selection timing.'
                    : 'Dữ liệu hiện tại không nêu thời điểm chọn chuyên ngành.',
              ),
          ],
        ),
      ],
    );
    return AskFptResponse(
      text: content.toPlainText(),
      state: AskFptResponseState.answered,
      source: '$curriculum / Professional specialization slots',
      content: content,
    );
  }

  static bool _isSpecializationReset(String question) {
    final text = normalizeCurriculumSearchText(question);
    return RegExp(
      r'\b(bo|xoa|clear|reset|remove|forget)\b.*\b(chuyen nganh|specialization|combo)\b',
    ).hasMatch(text);
  }

  static bool _isAmbiguousMajorStatement(String question) {
    final text = normalizeCurriculumSearchText(question);
    return RegExp(
      r'^(toi|minh|i)\s+(hoc|study)\s+(se|software engineering)$',
    ).hasMatch(text);
  }

  static bool _isSpecializationQuery(String text) => RegExp(
    r'\b(chuyen nganh cua (toi|minh) la gi|what is my specialization|my specialization)\b',
  ).hasMatch(text);

  static bool _isSpecializationExplanation(String text) => RegExp(
    r'\b(chuyen nganh la gi|tai sao.*chuyen nganh|khi nao.*chon.*chuyen nganh)\b',
  ).hasMatch(text);

  static bool _isSpecializationList(String text) =>
      RegExp(r'\b(chuyen nganh|specialization|combo)\b').hasMatch(text) &&
      RegExp(
        r'\b(danh sach|nhung|cac|co the chon|lua chon|list|options|available)\b',
      ).hasMatch(text);

  static bool _isBareSpecializationChange(String text) => RegExp(
    r'^(doi|thay doi|change|switch)\s+(chuyen nganh|specialization|combo)$',
  ).hasMatch(text.trim());

  Future<Map<String, dynamic>?> _subjectContext(
    String code,
    AskFptIntent intent,
  ) async {
    final json = await repository.loadSubject(code);
    if (json == null) return null;
    final base = <String, dynamic>{'code': code};
    switch (intent) {
      case AskFptIntent.subjectAssessment:
        base['assessments'] = json['assessments'];
      case AskFptIntent.subjectPrerequisite:
        base['prerequisite'] = json['prerequisite'];
      case AskFptIntent.subjectMaterials:
        base['learningMaterials'] = json['learningMaterials'];
      case AskFptIntent.subjectOutcomes:
        base['learningOutcomes'] = json['learningOutcomes'];
      case AskFptIntent.subjectCredits:
        base['credits'] = json['credits'];
      default:
        base.addAll({
          'syllabusName': json['syllabusName'],
          'englishName': json['englishName'],
          'credits': json['credits'],
          'minimumPassMark': json['minimumPassMark'],
          'prerequisite': json['prerequisite'],
          'description': json['description'],
        });
    }
    return base;
  }

  Future<Map<String, dynamic>?> _curriculumContext(
    String code,
    AskFptIntent intent,
    int? semester,
  ) async {
    final curriculum = await repository.loadCurriculum(code);
    if (curriculum == null) return null;
    if (intent == AskFptIntent.specializationOverview) {
      final values = await repository.loadProfessionalSpecializations(code);
      return {
        'curriculumCode': code,
        'specializations': [
          for (final value in values)
            {
              'name': _friendlySpecializationName(value),
              'sourceName': value.name,
              'note': value.note,
              'subjects': [
                for (final item in value.subjects)
                  {
                    'code': item.code,
                    'name': item.name,
                    'semester': item.semester,
                  },
              ],
            },
        ],
      };
    }
    if (intent == AskFptIntent.compareSpecializationAndCore) {
      final selected = _selectedSpecialization(code);
      if (selected == null) return null;
      final core = curriculum.subjects
          .where((item) => !item.isComboPlaceholder)
          .toList();
      return {
        'displayName': await _friendlyCurriculumLabel(code),
        'specialization': _friendlySpecializationName(selected),
        'coreSubjects': [
          for (final item in core)
            {
              'code': item.code,
              'name': item.name,
              'semester': item.semester,
              'credits': item.credits,
            },
        ],
        'specializationSubjects': [
          for (final item in selected.subjects)
            {'code': item.code, 'name': item.name, 'semester': item.semester},
        ],
      };
    }
    if (intent == AskFptIntent.personalCurriculumSubjects) {
      final selected = _selectedSpecialization(code);
      final activeSubjects = _mergeCurriculumSubjects(
        curriculum.subjects.where((item) => !item.isComboPlaceholder),
        selected,
      );
      final semesters =
          activeSubjects.map((item) => item.semester).toSet().toList()..sort();
      return {
        'curriculumCode': code,
        'name': curriculum.name,
        'displayName': await _friendlyCurriculumLabel(code),
        if (selected != null)
          'specialization': _friendlySpecializationName(selected),
        'semesters': [
          for (final semester in semesters)
            {
              'semester': semester,
              'subjects': [
                for (final item in activeSubjects.where(
                  (item) => item.semester == semester,
                ))
                  {
                    'code': item.code,
                    'name': item.name,
                    'credits': item.credits,
                  },
              ],
            },
        ],
      };
    }
    if (semester != null ||
        intent == AskFptIntent.semesterSubjects ||
        intent == AskFptIntent.futureSemester) {
      final requested = semester;
      if (requested == null) return null;
      final selected = _selectedSpecialization(code);
      final subjects = _mergeCurriculumSubjects(
        curriculum.subjects.where(
          (item) => item.semester == requested && !item.isComboPlaceholder,
        ),
        selected,
        semester: requested,
      );
      return {
        'curriculumCode': code,
        'displayName': await _friendlyCurriculumLabel(code),
        'semester': requested,
        if (selected != null)
          'specialization': _friendlySpecializationName(selected),
        'subjects': [
          for (final item in subjects)
            {
              'code': item.code,
              'name': item.name,
              'credits': item.credits,
              'prerequisite': item.prerequisite,
            },
        ],
      };
    }
    return {
      'curriculumCode': code,
      'name': curriculum.name,
      'displayName': await _friendlyCurriculumLabel(code),
      'totalCredits': curriculum.totalCredits,
      'subjectCount': curriculum.subjects.length,
      'semesters':
          curriculum.subjects.map((item) => item.semester).toSet().toList()
            ..sort(),
    };
  }

  Future<_SubjectResolution> _resolveSubject(String question) async {
    final normalized = normalizeCurriculumSearchText(question);
    if (recentSubject != null &&
        RegExp(r'\b(no|mon nay|it|this subject)\b').hasMatch(normalized)) {
      return _SubjectResolution(recentSubject);
    }
    final tokens =
        RegExp(r'\b[A-Za-z]{2,6}\d{0,4}[A-Za-z]?\b')
            .allMatches(question)
            .map((match) => match.group(0)!.toUpperCase())
            .where((token) => !_stopWords.contains(token))
            .toList()
          ..sort(
            (a, b) => b
                .contains(RegExp(r'\d'))
                .toString()
                .compareTo(a.contains(RegExp(r'\d')).toString()),
          );
    for (final token in tokens) {
      final matches = await repository.findSubjectCodes(token);
      if (matches.isEmpty) continue;
      final exact = matches
          .where((item) => item.code.toUpperCase() == token)
          .toList();
      if (exact.isNotEmpty) return _SubjectResolution(exact.first.code);
      final active = await _activeCurriculum();
      if (active != null) {
        final curriculum = await repository.loadCurriculum(active);
        final preferred = matches
            .where(
              (match) =>
                  curriculum?.subjects.any(
                    (subject) =>
                        subject.code.toUpperCase() == match.code.toUpperCase(),
                  ) ??
                  false,
            )
            .toList();
        if (preferred.length == 1) {
          return _SubjectResolution(preferred.first.code);
        }
      }
      if (matches.length == 1) return _SubjectResolution(matches.first.code);
      if (matches.length == 2) {
        final sorted = [...matches]..sort((a, b) => b.code.compareTo(a.code));
        return _SubjectResolution(sorted.first.code);
      }
      return _SubjectResolution(
        null,
        matches.take(6).map((item) => item.code).toList(),
      );
    }
    return const _SubjectResolution(null);
  }

  Future<String?> _activeCurriculum() async {
    final curriculum = studentContext.curriculum;
    if (!studentContext.hasVerifiedCurriculum || curriculum == null) {
      return null;
    }
    return await repository.containsCurriculum(curriculum) ? curriculum : null;
  }

  Future<void> _restoreSpecializationFor(
    String curriculum, {
    bool markRestored = false,
  }) async {
    var selected = await settings.getSpecialization(curriculum);
    if (selected != null) {
      final professional = await repository.loadProfessionalSpecializations(
        curriculum,
      );
      final valid = professional.any((choice) => choice.name == selected!.name);
      if (!valid) {
        await settings.clearSpecialization(curriculum);
        selected = null;
      }
    }
    var provenance = await settings.getSpecializationProvenance(curriculum);
    if (selected != null && markRestored) {
      await settings.markSpecializationRestored(curriculum);
      provenance = await settings.getSpecializationProvenance(curriculum);
    }
    studentContext.specialization = selected;
    studentContext.specializationProvenance = selected == null
        ? SpecializationProvenance.none
        : provenance;
  }

  SpecializationCombo? _selectedSpecialization(String curriculum) {
    if (studentContext.curriculum?.toUpperCase() != curriculum.toUpperCase()) {
      return null;
    }
    if (studentContext.specializationProvenance ==
        SpecializationProvenance.none) {
      return null;
    }
    return studentContext.specialization;
  }

  Future<void> _setSpecialization(
    String curriculum,
    SpecializationCombo selected,
  ) async {
    await settings.setSpecialization(
      curriculum,
      selected,
      provenance: SpecializationProvenance.explicitUserSelection,
    );
    studentContext.specialization = selected;
    studentContext.specializationProvenance =
        SpecializationProvenance.explicitUserSelection;
  }

  Future<void> _clearSelectedSpecialization(String curriculum) async {
    await settings.clearSpecialization(curriculum);
    if (studentContext.curriculum?.toUpperCase() == curriculum.toUpperCase()) {
      studentContext.specialization = null;
      studentContext.specializationProvenance = SpecializationProvenance.none;
    }
  }

  Future<AskFptResponse> _exportSubject(String code, bool english) async {
    try {
      final result = await exporter.addSubjectToMyNotes(code);
      if (result == null) return _cancelledExport(english);
      final subject = await repository.loadSubject(code);
      final rawName = subject?['syllabusName']?.toString().trim();
      final name = rawName == null ? null : _friendlySubjectName(rawName, true);
      final title = name == null || name.isEmpty ? code : '$code — $name';
      final content = AskFptContent(
        title: result.created
            ? (english ? 'Note created' : 'Đã tạo ghi chú')
            : (english ? 'Note already exists' : 'Ghi chú đã có'),
        summary: result.created
            ? title
            : (english
                  ? '$title is already in My Notes.'
                  : 'Ghi chú $title đã có trong My Notes.'),
        sections: [
          if (result.created)
            AskFptSection(
              type: AskFptSectionType.bulletList,
              heading: english ? 'Saved content' : 'Nội dung đã lưu',
              items: const [
                AskFptSectionItem(label: '', value: 'Tổng quan môn học'),
                AskFptSectionItem(label: '', value: 'Nội dung chính'),
                AskFptSectionItem(label: '', value: 'Assessment'),
                AskFptSectionItem(label: '', value: 'Materials'),
              ],
            ),
          AskFptSection(
            type: AskFptSectionType.info,
            items: [
              AskFptSectionItem(
                label: '',
                value: english
                    ? 'The note is saved and can be edited in Obsidian.'
                    : 'Ghi chú đã được lưu và có thể chỉnh sửa trong Obsidian.',
              ),
            ],
          ),
        ],
        actions: [
          AskFptAction(
            type: AskFptActionType.viewMyNotes,
            label: 'View in My Notes',
            value: 'subject:$code',
          ),
          AskFptAction(
            type: AskFptActionType.openObsidian,
            label: 'Open in Obsidian',
            value: 'subject:$code',
          ),
        ],
      );
      return AskFptResponse(
        text: content.toPlainText(),
        state: AskFptResponseState.notesSuccess,
        source: '$code / Local JSON export',
        content: content,
      );
    } catch (error) {
      return _failedExport(english, error);
    }
  }

  Future<AskFptResponse> _exportSemester(
    String curriculum,
    int semester,
    bool english,
  ) async {
    try {
      final result = await exporter.exportSemester(curriculum, semester);
      if (result == null) return _cancelledExport(english);
      return AskFptResponse(
        text: english
            ? 'Exported semester $semester and ${result.exportedSubjects} subjects from local JSON.'
            : 'Đã xuất học kỳ $semester và ${result.exportedSubjects} môn từ JSON cục bộ.',
        state: AskFptResponseState.notesSuccess,
        source: '$curriculum / Semester $semester export',
      );
    } catch (error) {
      return _failedExport(english, error);
    }
  }

  Future<AskFptResponse> _exportCurriculum(
    String curriculum,
    bool english,
  ) async {
    try {
      final result = await exporter.addCurriculumToMyNotes(curriculum);
      if (result == null) return _cancelledExport(english);
      return AskFptResponse(
        text: english
            ? 'Added $curriculum to My Notes from the local database.'
            : 'Đã thêm $curriculum vào My Notes từ dữ liệu cục bộ.',
        state: AskFptResponseState.notesSuccess,
        source: '$curriculum / Local JSON export',
        content: AskFptContent(
          title: english ? 'Curriculum note created' : 'Đã tạo ghi chú',
          summary: await _friendlyCurriculumLabel(curriculum),
          actions: [
            AskFptAction(
              type: AskFptActionType.viewMyNotes,
              label: 'View in My Notes',
              value: 'curriculum:$curriculum',
            ),
            AskFptAction(
              type: AskFptActionType.openObsidian,
              label: 'Open in Obsidian',
              value: 'curriculum:$curriculum',
            ),
          ],
        ),
      );
    } catch (error) {
      return _failedExport(english, error);
    }
  }

  AskFptResponse _cancelledExport(bool english) => AskFptResponse(
    text: english ? 'Export was cancelled.' : 'Đã hủy xuất ghi chú.',
    state: AskFptResponseState.notesFailure,
  );

  AskFptResponse _failedExport(bool english, Object error) => AskFptResponse(
    text: english
        ? 'Could not export Markdown: $error'
        : 'Không thể xuất Markdown: $error',
    state: AskFptResponseState.notesFailure,
  );

  AskFptContent _localSubjectContent(
    String code,
    Map<String, dynamic> context,
    AskFptIntent intent,
    bool english,
  ) {
    if (intent == AskFptIntent.subjectAssessment) {
      final rows = (context['assessments'] as List? ?? const [])
          .whereType<Map>();
      final pe = rows.any(
        (item) => (item['category']?.toString().toLowerCase() ?? '').contains(
          'practical',
        ),
      );
      return AskFptContent(
        title: '$code — Assessment',
        summary: english
            ? '$code ${pe ? 'has' : 'does not show'} a Practical Exam in the database.'
            : '$code ${pe ? 'có' : 'không thấy'} Practical Exam (PE) trong dữ liệu.',
        sections: [
          AskFptSection(
            type: AskFptSectionType.assessmentList,
            heading: 'Assessment',
            items: [
              for (final item in rows)
                AskFptSectionItem(
                  label: item['category']?.toString() ?? '',
                  value: item['weight']?.toString() ?? '',
                  detail: item['note']?.toString(),
                ),
            ],
          ),
        ],
      );
    }
    if (intent == AskFptIntent.subjectPrerequisite) {
      final value = context['prerequisite']?.toString().trim() ?? '';
      return AskFptContent(
        title: code,
        sections: [
          AskFptSection(
            type: AskFptSectionType.keyValue,
            items: [
              AskFptSectionItem(
                label: english ? 'Prerequisite' : 'Môn tiên quyết',
                value: value.isEmpty
                    ? (english ? 'None listed' : 'Không có')
                    : value,
              ),
            ],
          ),
        ],
      );
    }
    if (intent == AskFptIntent.subjectCredits) {
      return AskFptContent(
        title: code,
        sections: [
          AskFptSection(
            type: AskFptSectionType.keyValue,
            items: [
              AskFptSectionItem(
                label: english ? 'Credits' : 'Tín chỉ',
                value: context['credits']?.toString() ?? '',
              ),
            ],
          ),
        ],
      );
    }
    if (intent == AskFptIntent.subjectMaterials) {
      return AskFptContent(
        title: english ? '$code — Materials' : '$code — Tài liệu',
        sections: [
          AskFptSection(
            type: AskFptSectionType.bulletList,
            items: [
              for (final item
                  in (context['learningMaterials'] as List? ?? const [])
                      .whereType<Map>())
                if ((item['description']?.toString().trim() ?? '').isNotEmpty)
                  AskFptSectionItem(
                    label: '',
                    value: item['description'].toString(),
                  ),
            ],
          ),
        ],
      );
    }
    if (intent == AskFptIntent.subjectOutcomes) {
      return AskFptContent(
        title: english ? '$code — Learning outcomes' : '$code — Chuẩn đầu ra',
        sections: [
          AskFptSection(
            type: AskFptSectionType.bulletList,
            items: [
              for (final item
                  in (context['learningOutcomes'] as List? ?? const []))
                AskFptSectionItem(label: '', value: item.toString()),
            ],
          ),
        ],
      );
    }
    final name = _friendlySubjectName(
      context['syllabusName']?.toString() ?? code,
      english,
    );
    final description = context['description']?.toString().trim() ?? '';
    final short = description.length > 420
        ? '${description.substring(0, 420)}…'
        : description;
    return AskFptContent(
      title: '$code — $name',
      summary: short,
      sections: [
        AskFptSection(
          type: AskFptSectionType.keyValue,
          items: [
            AskFptSectionItem(
              label: english ? 'Credits' : 'Tín chỉ',
              value: context['credits']?.toString() ?? '',
            ),
            AskFptSectionItem(
              label: english ? 'Prerequisite' : 'Môn tiên quyết',
              value: context['prerequisite']?.toString().trim().isEmpty ?? true
                  ? (english ? 'None listed' : 'Không có')
                  : context['prerequisite'].toString(),
            ),
          ],
        ),
      ],
    );
  }

  AskFptContent _localCurriculumContent(
    Map<String, dynamic> context,
    bool english,
  ) {
    if (context['semesters'] is List &&
        (context['semesters'] as List).whereType<Map>().any(
          (item) => item['subjects'] is List,
        )) {
      final display =
          context['displayName']?.toString() ??
          context['name']?.toString() ??
          context['curriculumCode']?.toString() ??
          '';
      return AskFptContent(
        title: display,
        summary: english
            ? 'Your active curriculum subjects are grouped by semester.'
            : 'Các môn trong chương trình của bạn được chia theo học kỳ.',
        sections: [
          for (final item in (context['semesters'] as List).whereType<Map>())
            AskFptSection(
              type: AskFptSectionType.subjectList,
              heading: item['semester'] == 0
                  ? (english ? 'Preparation' : 'Chuẩn bị')
                  : (english
                        ? 'Semester ${item['semester']}'
                        : 'Học kỳ ${item['semester']}'),
              items: _subjectItems(item['subjects'], english: english),
            ),
        ],
      );
    }
    if (context['subjects'] is List) {
      final semester = context['semester'];
      final subjects = _subjectItems(context['subjects'], english: english);
      final specialization = context['specialization']?.toString().trim();
      return AskFptContent(
        title: english ? 'Semester $semester' : 'Học kỳ $semester',
        summary: english
            ? 'You will study ${subjects.length} subjects.'
            : 'Bạn sẽ học ${subjects.length} môn.',
        sections: [
          AskFptSection(
            type: AskFptSectionType.subjectList,
            heading: english ? 'Subjects' : 'Môn học',
            items: subjects,
          ),
          if (specialization != null && specialization.isNotEmpty)
            AskFptSection(
              type: AskFptSectionType.info,
              items: [
                AskFptSectionItem(
                  label: english ? 'Specialization' : 'Chuyên ngành',
                  value: specialization,
                ),
              ],
            ),
        ],
      );
    }
    if (context['specializations'] is List) {
      return AskFptContent(
        title: english ? 'Specializations' : 'Chuyên ngành',
        sections: [
          AskFptSection(
            type: AskFptSectionType.specializationList,
            items: [
              for (final item
                  in (context['specializations'] as List).whereType<Map>())
                AskFptSectionItem(
                  label: '',
                  value: item['name']?.toString() ?? '',
                ),
            ],
          ),
        ],
      );
    }
    if (context['coreSubjects'] is List) {
      final specialization = context['specialization']?.toString() ?? '';
      return AskFptContent(
        title: english
            ? 'Core and specialization subjects'
            : 'Môn chung và môn chuyên ngành',
        summary: english
            ? 'The local curriculum separates core subjects from $specialization.'
            : 'Chương trình cục bộ phân tách môn chung và chuyên ngành $specialization.',
        sections: [
          AskFptSection(
            type: AskFptSectionType.subjectList,
            heading: english ? 'Core subjects' : 'Môn ngoài chuyên ngành',
            items: _subjectItems(context['coreSubjects'], english: english),
          ),
          AskFptSection(
            type: AskFptSectionType.subjectList,
            heading: specialization,
            items: _subjectItems(
              context['specializationSubjects'],
              english: english,
            ),
          ),
        ],
      );
    }
    return AskFptContent(
      title:
          context['displayName']?.toString() ??
          context['name']?.toString() ??
          '',
      sections: [
        AskFptSection(
          type: AskFptSectionType.keyValue,
          items: [
            AskFptSectionItem(
              label: english ? 'Subject slots' : 'Môn/học phần',
              value: context['subjectCount']?.toString() ?? '',
            ),
            AskFptSectionItem(
              label: english ? 'Total credits' : 'Tổng tín chỉ',
              value:
                  context['totalCredits']?.toString() ??
                  (english ? 'Unknown' : 'Chưa rõ'),
            ),
          ],
        ),
      ],
    );
  }

  List<AskFptSectionItem> _subjectItems(Object? raw, {bool english = false}) =>
      (raw as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AskFptSectionItem(
              label: item['code']?.toString() ?? '',
              value: _friendlySubjectName(
                item['name']?.toString() ?? '',
                english,
              ),
              detail:
                  (item['credits']?.toString().isNotEmpty ?? false) &&
                      item['credits']?.toString() != '0'
                  ? (english
                        ? '${item['credits']} credits'
                        : '${item['credits']} tín chỉ')
                  : item['semester'] == null
                  ? null
                  : (english
                        ? 'Semester ${item['semester']}'
                        : 'Học kỳ ${item['semester']}'),
            ),
          )
          .toList();

  String _friendlySubjectName(String raw, bool english) {
    final parts = raw
        .split(RegExp(r'_+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return raw.trim();
    return english || parts.length == 1 ? parts.first : parts.last;
  }

  Future<bool> _requiresSpecialization(String code, int semester) async {
    final choices = await repository.loadProfessionalSpecializations(code);
    if (choices.isEmpty) return false;
    if (choices.any(
      (choice) =>
          choice.subjects.any((subject) => subject.semester == semester),
    )) {
      return true;
    }
    return false;
  }

  Future<SpecializationCombo?> _matchSpecialization(
    String curriculum,
    String answer,
  ) async {
    final normalized = normalizeCurriculumSearchText(answer);
    final choices = await repository.loadProfessionalSpecializations(
      curriculum,
    );
    SpecializationCombo? best;
    var bestIndex = -1;
    for (final choice in choices) {
      final friendly = normalizeCurriculumSearchText(
        _friendlySpecializationName(choice),
      );
      final candidates = {
        normalizeCurriculumSearchText(choice.name),
        friendly,
        normalizeCurriculumSearchText(choice.note),
      }..removeWhere((value) => value.isEmpty);
      for (final candidate in candidates) {
        final matches = RegExp(
          '(?:^|[^a-z0-9])${RegExp.escape(candidate)}(?=\$|[^a-z0-9])',
        ).allMatches(normalized);
        final index = matches.isEmpty ? -1 : matches.last.start;
        if (index >= bestIndex && index >= 0) {
          best = choice;
          bestIndex = index;
        }
      }
      for (final token in friendly.split(' ')) {
        if (token.length < 4 || _specializationMatchStopWords.contains(token)) {
          continue;
        }
        final tokenMatches = RegExp(
          '(?:^|[^a-z0-9])${RegExp.escape(token)}(?=\$|[^a-z0-9])',
        ).allMatches(normalized);
        final tokenIndex = tokenMatches.isEmpty ? -1 : tokenMatches.last.start;
        if (tokenIndex >= bestIndex && tokenIndex >= 0) {
          best = choice;
          bestIndex = tokenIndex;
        }
      }
    }
    return best;
  }

  Future<AskFptResponse> _specializationClarification(
    String curriculum,
    bool english, {
    bool keepPending = false,
    bool invalidSelection = false,
  }) async {
    final choices = await repository.loadProfessionalSpecializations(
      curriculum,
    );
    if (choices.isEmpty) {
      final message = english
          ? 'The current database does not list a professional specialization for this curriculum.'
          : 'Dữ liệu hiện tại không có chuyên ngành chuyên môn nào cho chương trình này.';
      return AskFptResponse(
        text: message,
        state: AskFptResponseState.answered,
        source: '$curriculum / Professional specialization slots',
        content: AskFptContent(summary: message),
      );
    }
    final actions = [
      for (final choice in choices)
        AskFptAction(
          type: AskFptActionType.selectSpecialization,
          label: _friendlySpecializationName(choice),
          value: english
              ? 'my specialization is ${_friendlySpecializationName(choice)}'
              : 'chuyên ngành của tôi là ${_friendlySpecializationName(choice)}',
        ),
    ];
    final content = AskFptContent(
      title: english ? 'Choose a specialization' : 'Chọn chuyên ngành',
      summary: invalidSelection
          ? (english
                ? 'That specialization is not available for this curriculum. Choose one of the real options below.'
                : 'Chuyên ngành đó không có trong chương trình này. Bạn chọn một phương án thực tế bên dưới nhé.')
          : (english
                ? 'Which specialization are you following? I need it to fill the correct specialization subjects.'
                : 'Bạn đang theo chuyên ngành nào? Mình cần thông tin này để xác định đúng các môn chuyên ngành.'),
      sections: [
        AskFptSection(
          type: AskFptSectionType.specializationList,
          heading: english ? 'Available options' : 'Các lựa chọn hiện có',
          items: [
            for (final choice in choices)
              AskFptSectionItem(
                label: _friendlySpecializationName(choice),
                value: english
                    ? '${choice.subjects.length} subjects'
                    : '${choice.subjects.length} môn chuyên ngành',
              ),
          ],
        ),
      ],
      actions: actions,
    );
    if (!keepPending) await _persistSession();
    return AskFptResponse(
      text: content.toPlainText(),
      state: AskFptResponseState.clarification,
      source: '$curriculum / Specializations',
      content: content,
    );
  }

  List<DatabaseCurriculumSubject> _mergeCurriculumSubjects(
    Iterable<DatabaseCurriculumSubject> core,
    SpecializationCombo? specialization, {
    int? semester,
  }) {
    final values = <String, DatabaseCurriculumSubject>{
      for (final subject in core) subject.code.toUpperCase(): subject,
    };
    if (specialization != null) {
      for (final subject in specialization.subjects) {
        if (semester != null && subject.semester != semester) continue;
        values.putIfAbsent(
          subject.code.toUpperCase(),
          () => DatabaseCurriculumSubject(
            code: subject.code,
            name: subject.name,
            semester: subject.semester,
            credits: 0,
            prerequisite: '',
            isComboPlaceholder: false,
          ),
        );
      }
    }
    final result = values.values.toList()
      ..sort((a, b) {
        final bySemester = a.semester.compareTo(b.semester);
        return bySemester != 0 ? bySemester : a.code.compareTo(b.code);
      });
    return result;
  }

  String _friendlySpecializationName(SpecializationCombo choice) {
    var name = choice.name.trim();
    if (name.toUpperCase().startsWith('PHE_COM1:')) return 'Vovinam';
    if (name.toUpperCase().startsWith('PHE_COM2:')) return 'Cờ vua';
    if (name.toUpperCase().startsWith('SE_COM10.2:')) {
      return 'Java chuyên sâu';
    }
    name = name.replaceFirst(RegExp(r'^[A-Z]+_[A-Z0-9.]+:\s*'), '');
    name = name.replaceFirst(
      RegExp(r'\s+BIT_[A-Z]{2,4}.*$', caseSensitive: false),
      '',
    );
    final vietnamese = name.split('_').where((part) {
      final value = part.trim();
      return value.isNotEmpty &&
          !RegExp(
            r'^(K\d+|BIT(?:_|$)|SE(?:_|$))',
            caseSensitive: false,
          ).hasMatch(value);
    }).toList();
    if (vietnamese.length > 1) name = vietnamese.last.trim();
    return name.replaceFirst(RegExp(r'^Chủ đề\s+', caseSensitive: false), '');
  }

  Future<String> _friendlyCurriculumLabel(String code) async {
    final profile = resolvedProfile;
    if (profile != null &&
        profile.primaryCurriculum.toUpperCase() == code.toUpperCase()) {
      return '${_friendlyMajor(profile.majorPrefix)} — khóa K${profile.cohort}';
    }
    final match = RegExp(
      r'_([A-Z]{2,4})_K(\d{2})',
    ).firstMatch(code.toUpperCase());
    if (match != null) {
      return '${_friendlyMajor(match.group(1)!)} — khóa K${match.group(2)}';
    }
    final curriculum = await repository.loadCurriculum(code);
    final name = curriculum?.name.trim() ?? '';
    return name.isEmpty ? code : name;
  }

  String _friendlyMajor(String prefix) => switch (prefix.toUpperCase()) {
    'SE' => 'Software Engineering',
    'AI' => 'Artificial Intelligence',
    'IA' => 'Information Assurance',
    'GD' => 'Graphic Design',
    _ => prefix.toUpperCase(),
  };

  Future<void> _restoreSession() async {
    final session = await settings.getAskFptSession();
    if (session == null) return;
    final rawMessages = session['messages'];
    if (rawMessages is List) {
      messages.addAll(
        rawMessages
            .whereType<Map>()
            .map(
              (raw) =>
                  AskFptChatMessage.fromJson(Map<String, dynamic>.from(raw)),
            )
            .take(100),
      );
    }
    recentSubject = session['recentSubject']?.toString();
    final savedRecentCurriculum = session['recentCurriculum']?.toString();
    if (recentCurriculum == null &&
        activeProvenance != ActiveContextProvenance.none) {
      recentCurriculum = savedRecentCurriculum;
    }
    final intentName = session['recentIntent']?.toString();
    recentIntent = AskFptIntent.values.where((item) {
      return item.name == intentName;
    }).firstOrNull;
    _pendingQuestion = session['pendingQuestion']?.toString();
    _pendingSpecializationCurriculum =
        session['pendingSpecializationCurriculum']?.toString();
    notifyListeners();
  }

  Future<void> _persistSession() => settings.setAskFptSession({
    'version': 1,
    'messages': messages.map((message) => message.toJson()).toList(),
    if (recentSubject != null) 'recentSubject': recentSubject,
    if (recentCurriculum != null) 'recentCurriculum': recentCurriculum,
    if (recentIntent != null) 'recentIntent': recentIntent!.name,
    if (_pendingQuestion != null) 'pendingQuestion': _pendingQuestion,
    if (_pendingSpecializationCurriculum != null)
      'pendingSpecializationCurriculum': _pendingSpecializationCurriculum,
  });

  static bool _isSubjectIntent(AskFptIntent intent) => {
    AskFptIntent.subjectOverview,
    AskFptIntent.subjectAssessment,
    AskFptIntent.subjectPrerequisite,
    AskFptIntent.subjectMaterials,
    AskFptIntent.subjectOutcomes,
    AskFptIntent.subjectCredits,
    AskFptIntent.notesAddSubject,
  }.contains(intent);

  static String _sourcePart(AskFptIntent intent) => switch (intent) {
    AskFptIntent.subjectAssessment => 'Assessment',
    AskFptIntent.subjectPrerequisite => 'Prerequisite',
    AskFptIntent.subjectMaterials => 'Materials',
    AskFptIntent.subjectOutcomes => 'Learning outcomes',
    AskFptIntent.subjectCredits => 'Credits',
    _ => 'Overview',
  };

  static bool _isEnglish(String value) => RegExp(
    r'\b(what|which|does|is|are|course|semester|subject|my|please)\b',
    caseSensitive: false,
  ).hasMatch(value);

  static bool _containsAcademicQuestionBesidesId(String value) {
    final stripped = value.replaceAll(
      RegExp(r'[A-Za-z]{2,4}\s*[-_]?\s*\d{5,}'),
      '',
    );
    return RegExp(
      r'\b(ky|hoc|mon|semester|subject|course|curriculum|specialization)\b',
      caseSensitive: false,
    ).hasMatch(normalizeCurriculumSearchText(stripped));
  }

  static String _redactStudentId(String value) => value
      .replaceAll(
        RegExp(
          r'(?:^|[^A-Za-z0-9])[A-Za-z]{2,4}\s*[-_]?\s*\d{2}\s*[-_]?\s*\d{3,}(?=$|[^A-Za-z0-9])',
        ),
        ' [student profile resolved locally] ',
      )
      .trim();

  static const _stopWords = {
    'MON',
    'NAY',
    'CO',
    'KHONG',
    'K0',
    'KO',
    'THI',
    'HOC',
    'GI',
    'LA',
    'THE',
    'WHAT',
    'WHICH',
    'DOES',
    'THIS',
    'SUBJECT',
    'COURSE',
    'WITH',
    'ABOUT',
    'THEM',
    'LUU',
    'XUAT',
    'GHI',
    'CHU',
    'NOTES',
    'OBSIDIAN',
    'VAO',
    'CHO',
  };

  static const _specializationMatchStopWords = {
    'topic',
    'chuyen',
    'nganh',
    'chu de',
    'chuong',
    'trinh',
    'phat',
    'trien',
    'development',
    'programming',
  };
}

class _SubjectResolution {
  final String? code;
  final List<String> ambiguous;

  const _SubjectResolution(this.code, [this.ambiguous = const []]);
}
