import '../flm/flm_combo_service.dart';
import '../flm/flm_syllabus_service.dart';
import '../models/curriculum_subject.dart';

class CollectedCurriculumData {
  final String code;
  final String? name;
  final int? totalCredits;
  final List<CurriculumSubject> subjects;
  final List<SpecializationCombo> specializations;

  const CollectedCurriculumData({
    required this.code,
    required this.name,
    required this.totalCredits,
    required this.subjects,
    required this.specializations,
  });

  Map<String, dynamic> curriculumJson(DateTime fetchedAt) {
    final semesters = <int, List<CurriculumSubject>>{};
    for (final subject in subjects) {
      semesters.putIfAbsent(subject.semester, () => []).add(subject);
    }

    final semesterNumbers = semesters.keys.toList()..sort();
    return {
      'code': code,
      'name': name,
      'totalCredits': totalCredits,
      'fetchedAt': fetchedAt.toUtc().toIso8601String(),
      'semesters': [
        for (final semester in semesterNumbers)
          {
            'semester': semester,
            'subjects': [
              for (final subject
                  in semesters[semester]!
                    ..sort((a, b) => a.code.compareTo(b.code)))
                {
                  'code': subject.code,
                  'name': subject.name,
                  'credits': subject.credits,
                  'prerequisite': subject.prerequisite.trim().isEmpty
                      ? null
                      : subject.prerequisite,
                  'isComboPlaceholder': subject.isComboPlaceholder,
                },
            ],
          },
      ],
    };
  }

  Map<String, dynamic> specializationsJson(DateTime fetchedAt) {
    return {
      'curriculumCode': code,
      'specializations': [
        for (final specialization in specializations)
          {
            'name': specialization.name,
            'note': specialization.note,
            'detailUrl': specialization.detailUrl,
            'subjects': [
              for (final subject in specialization.subjects)
                {
                  'code': subject.code,
                  'name': subject.name,
                  'semester': subject.semester,
                },
            ],
          },
      ],
      'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    };
  }

  Set<String> get uniqueSubjectCodes => {
    for (final subject in subjects)
      if (!subject.isComboPlaceholder && subject.code.trim().isNotEmpty)
        subject.code.trim().toUpperCase(),
    for (final specialization in specializations)
      for (final subject in specialization.subjects)
        if (subject.code.trim().isNotEmpty) subject.code.trim().toUpperCase(),
  };
}

Map<String, dynamic> syllabusJson(
  SyllabusDetailResult syllabus,
  DateTime fetchedAt,
) {
  return {
    'code': syllabus.subjectCode,
    'syllabusName': syllabus.syllabusName,
    'englishName': syllabus.courseNameEnglish,
    'credits': syllabus.credits,
    'minimumPassMark': syllabus.minimumPassMark,
    'prerequisite': syllabus.prerequisite,
    'description': syllabus.description,
    'teachingMethod': syllabus.teachingMethod,
    'timeAllocation': syllabus.timeAllocation,
    'studentTasks': syllabus.studentTasks,
    'tools': syllabus.tools,
    'learningMaterials': [
      for (final material in syllabus.materials)
        {
          'description': material.description,
          'author': material.author,
          'publisher': material.publisher,
          'publishedDate': material.publishedDate,
          'edition': material.edition,
          'isbn': material.isbn,
          'isMain': material.isMain,
          'isOnline': material.isOnline,
          'note': material.note,
        },
    ],
    'learningOutcomes': [
      for (final outcome in syllabus.outcomes)
        {'name': outcome.name, 'details': outcome.details},
    ],
    'assessments': [
      for (final assessment in syllabus.assessments)
        {
          'category': assessment.category,
          'type': assessment.type,
          'part': assessment.part,
          'weight': assessment.weight,
          'completionCriteria': assessment.completionCriteria,
          'duration': assessment.duration,
          'clo': assessment.clo,
          'questionType': assessment.questionType,
          'numberOfQuestions': assessment.numberOfQuestions,
          'knowledgeAndSkill': assessment.knowledgeAndSkill,
          'gradingGuide': assessment.gradingGuide,
          'note': assessment.note,
        },
    ],
    'sourceUrl': syllabus.url,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
  };
}

class FlmExtractionState {
  final String runStartedAt;
  final List<String> curriculaDiscovered;
  final List<String> curriculaCompleted;
  final List<String> subjectsDiscovered;
  final List<String> subjectsCompleted;
  final Map<String, String> failedCurricula;
  final Map<String, String> failedSubjects;
  final bool isComplete;
  final bool isPaused;
  final FlmRuntimeDiagnostics diagnostics;

  const FlmExtractionState({
    required this.runStartedAt,
    required this.curriculaDiscovered,
    required this.curriculaCompleted,
    required this.subjectsDiscovered,
    required this.subjectsCompleted,
    required this.failedCurricula,
    required this.failedSubjects,
    required this.isComplete,
    required this.isPaused,
    this.diagnostics = const FlmRuntimeDiagnostics(),
  });

  factory FlmExtractionState.fresh() {
    return FlmExtractionState(
      runStartedAt: DateTime.now().toUtc().toIso8601String(),
      curriculaDiscovered: const [],
      curriculaCompleted: const [],
      subjectsDiscovered: const [],
      subjectsCompleted: const [],
      failedCurricula: const {},
      failedSubjects: const {},
      isComplete: false,
      isPaused: false,
      diagnostics: const FlmRuntimeDiagnostics(),
    );
  }

  factory FlmExtractionState.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => (json[key] is List)
        ? (json[key] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList()
        : <String>[];
    Map<String, String> errors(String key) => json[key] is Map
        ? (json[key] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : <String, String>{};

    return FlmExtractionState(
      runStartedAt: json['runStartedAt']?.toString() ?? '',
      curriculaDiscovered: strings('curriculaDiscovered'),
      curriculaCompleted: strings('curriculaCompleted'),
      subjectsDiscovered: strings('subjectsDiscovered'),
      subjectsCompleted: strings('subjectsCompleted'),
      failedCurricula: errors('failedCurricula'),
      failedSubjects: errors('failedSubjects'),
      isComplete: json['isComplete'] == true,
      isPaused: json['isPaused'] == true,
      diagnostics: json['diagnostics'] is Map
          ? FlmRuntimeDiagnostics.fromJson(
              Map<String, dynamic>.from(json['diagnostics'] as Map),
            )
          : const FlmRuntimeDiagnostics(),
    );
  }

  Map<String, dynamic> toJson() => {
    'runStartedAt': runStartedAt,
    'curriculaDiscovered': curriculaDiscovered,
    'curriculaCompleted': curriculaCompleted,
    'subjectsDiscovered': subjectsDiscovered,
    'subjectsCompleted': subjectsCompleted,
    'failedCurricula': failedCurricula,
    'failedSubjects': failedSubjects,
    'isComplete': isComplete,
    'isPaused': isPaused,
    'diagnostics': diagnostics.toJson(),
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  FlmExtractionState copyWith({
    List<String>? curriculaDiscovered,
    List<String>? curriculaCompleted,
    List<String>? subjectsDiscovered,
    List<String>? subjectsCompleted,
    Map<String, String>? failedCurricula,
    Map<String, String>? failedSubjects,
    bool? isComplete,
    bool? isPaused,
    FlmRuntimeDiagnostics? diagnostics,
  }) {
    return FlmExtractionState(
      runStartedAt: runStartedAt,
      curriculaDiscovered: curriculaDiscovered ?? this.curriculaDiscovered,
      curriculaCompleted: curriculaCompleted ?? this.curriculaCompleted,
      subjectsDiscovered: subjectsDiscovered ?? this.subjectsDiscovered,
      subjectsCompleted: subjectsCompleted ?? this.subjectsCompleted,
      failedCurricula: failedCurricula ?? this.failedCurricula,
      failedSubjects: failedSubjects ?? this.failedSubjects,
      isComplete: isComplete ?? this.isComplete,
      isPaused: isPaused ?? this.isPaused,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }
}

class FlmRuntimeDiagnostics {
  final String currentUrl;
  final bool? loginDetected;
  final String stage;
  final int rowsFound;
  final int codesDiscovered;
  final String currentCurriculum;
  final String currentSubject;
  final String lastError;

  const FlmRuntimeDiagnostics({
    this.currentUrl = '',
    this.loginDetected,
    this.stage = '',
    this.rowsFound = 0,
    this.codesDiscovered = 0,
    this.currentCurriculum = '',
    this.currentSubject = '',
    this.lastError = '',
  });

  factory FlmRuntimeDiagnostics.fromJson(Map<String, dynamic> json) {
    return FlmRuntimeDiagnostics(
      currentUrl: json['currentUrl']?.toString() ?? '',
      loginDetected: json['loginDetected'] is bool
          ? json['loginDetected'] as bool
          : null,
      stage: json['stage']?.toString() ?? '',
      rowsFound: int.tryParse(json['rowsFound']?.toString() ?? '') ?? 0,
      codesDiscovered:
          int.tryParse(json['codesDiscovered']?.toString() ?? '') ?? 0,
      currentCurriculum: json['currentCurriculum']?.toString() ?? '',
      currentSubject: json['currentSubject']?.toString() ?? '',
      lastError: json['lastError']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'currentUrl': currentUrl,
    'loginDetected': loginDetected,
    'stage': stage,
    'rowsFound': rowsFound,
    'codesDiscovered': codesDiscovered,
    'currentCurriculum': currentCurriculum,
    'currentSubject': currentSubject,
    'lastError': lastError,
  };

  FlmRuntimeDiagnostics copyWith({
    String? currentUrl,
    bool? loginDetected,
    String? stage,
    int? rowsFound,
    int? codesDiscovered,
    String? currentCurriculum,
    String? currentSubject,
    String? lastError,
  }) {
    return FlmRuntimeDiagnostics(
      currentUrl: currentUrl ?? this.currentUrl,
      loginDetected: loginDetected ?? this.loginDetected,
      stage: stage ?? this.stage,
      rowsFound: rowsFound ?? this.rowsFound,
      codesDiscovered: codesDiscovered ?? this.codesDiscovered,
      currentCurriculum: currentCurriculum ?? this.currentCurriculum,
      currentSubject: currentSubject ?? this.currentSubject,
      lastError: lastError ?? this.lastError,
    );
  }
}

class ReleaseDatabaseResult {
  final String zipPath;
  final int curriculumCount;
  final int subjectCount;
  final int syllabusCount;

  const ReleaseDatabaseResult({
    required this.zipPath,
    required this.curriculumCount,
    required this.subjectCount,
    required this.syllabusCount,
  });
}

class FlmCollectionProgress {
  final String phase;
  final String currentItem;
  final int current;
  final int total;
  final FlmExtractionState state;

  const FlmCollectionProgress({
    required this.phase,
    required this.currentItem,
    required this.current,
    required this.total,
    required this.state,
  });
}
