import 'groq_ai_service.dart';

class AskFptPlan {
  static const allowedRetrievalTargets = {
    'subject',
    'curriculum',
    'semester',
    'specialization',
    'assessment',
    'materials',
  };

  final String domain;
  final String intent;
  final List<String> subjectCodes;
  final int? semester;
  final String? specialization;
  final bool requiresCurriculum;
  final bool requiresSemester;
  final bool requiresSpecialization;
  final bool clarificationNeeded;
  final String? clarificationQuestion;
  final List<String> retrievalTargets;

  const AskFptPlan({
    required this.domain,
    required this.intent,
    this.subjectCodes = const [],
    this.semester,
    this.specialization,
    this.requiresCurriculum = false,
    this.requiresSemester = false,
    this.requiresSpecialization = false,
    this.clarificationNeeded = false,
    this.clarificationQuestion,
    this.retrievalTargets = const [],
  });

  factory AskFptPlan.fromJson(Map<String, dynamic> json) {
    final entities = json['entities'] is Map
        ? Map<String, dynamic>.from(json['entities'] as Map)
        : const <String, dynamic>{};
    final requires = json['requires'] is Map
        ? Map<String, dynamic>.from(json['requires'] as Map)
        : const <String, dynamic>{};
    final rawTargets = json['retrievalTargets'];
    return AskFptPlan(
      domain: json['domain']?.toString().trim() ?? 'other',
      intent: json['intent']?.toString().trim() ?? 'unclear',
      subjectCodes: (entities['subjectCodes'] as List? ?? const [])
          .map((value) => value.toString().trim().toUpperCase())
          .where(
            (value) => RegExp(r'^[A-Z]{2,6}\d{2,4}[A-Z]?$').hasMatch(value),
          )
          .toList(),
      semester: int.tryParse(entities['semester']?.toString() ?? ''),
      specialization: _nullable(entities['specialization']),
      requiresCurriculum: requires['curriculum'] == true,
      requiresSemester: requires['semester'] == true,
      requiresSpecialization: requires['specialization'] == true,
      clarificationNeeded: json['clarificationNeeded'] == true,
      clarificationQuestion: _nullable(json['clarificationQuestion']),
      retrievalTargets: (rawTargets as List? ?? const [])
          .map((value) => value.toString().trim())
          .where(allowedRetrievalTargets.contains)
          .toSet()
          .toList(),
    );
  }

  static String? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? null : text;
  }
}

abstract class AskFptPlanner {
  Future<AskFptPlan?> plan({
    required String question,
    required Map<String, dynamic> knownContext,
    required bool english,
  });
}

class GroqAskFptPlanner implements AskFptPlanner {
  final GroqAiService groq;

  const GroqAskFptPlanner(this.groq);

  @override
  Future<AskFptPlan?> plan({
    required String question,
    required Map<String, dynamic> knownContext,
    required bool english,
  }) async {
    final result = await groq.plan(
      question: question,
      knownContext: knownContext,
      english: english,
    );
    final structured = result.structured;
    if (!result.isSuccess || structured == null) return null;
    return AskFptPlan.fromJson(structured);
  }
}
