import '../database/database_repository.dart';

class ParsedStudentId {
  final String majorPrefix;
  final int cohort;

  const ParsedStudentId({required this.majorPrefix, required this.cohort});
}

class ResolvedStudentProfile {
  final String majorPrefix;
  final int cohort;
  final String primaryCurriculum;
  final List<String> candidates;
  final List<String> commonSubjectCodes;

  const ResolvedStudentProfile({
    required this.majorPrefix,
    required this.cohort,
    required this.primaryCurriculum,
    required this.candidates,
    required this.commonSubjectCodes,
  });

  Map<String, dynamic> toJson() => {
    'majorPrefix': majorPrefix,
    'cohort': cohort,
    'primaryCurriculum': primaryCurriculum,
    'candidates': candidates,
    'commonSubjectCodes': commonSubjectCodes,
  };

  factory ResolvedStudentProfile.fromJson(Map<String, dynamic> json) =>
      ResolvedStudentProfile(
        majorPrefix: json['majorPrefix']?.toString() ?? '',
        cohort: int.tryParse(json['cohort']?.toString() ?? '') ?? 0,
        primaryCurriculum: json['primaryCurriculum']?.toString() ?? '',
        candidates: (json['candidates'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        commonSubjectCodes: (json['commonSubjectCodes'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
}

class StudentProfileResolver {
  final DatabaseRepository repository;

  const StudentProfileResolver(this.repository);

  ParsedStudentId? parse(String input) {
    final normalized = input.toUpperCase();
    final match = RegExp(
      r'(?:^|[^A-Z0-9])([A-Z]{2,4})\s*[-_]?\s*(\d{2})\s*[-_]?\s*(\d{3,})(?=$|[^A-Z0-9])',
    ).firstMatch(normalized);
    if (match == null) return null;
    return ParsedStudentId(
      majorPrefix: match.group(1)!,
      cohort: int.parse(match.group(2)!),
    );
  }

  Future<ResolvedStudentProfile?> resolve(ParsedStudentId student) async {
    final cohortToken = 'K${student.cohort}';
    final familyToken = '_${student.majorPrefix}_';
    final candidates = repository.curriculumCodes.where((code) {
      final upper = code.toUpperCase();
      return upper.contains(familyToken) && upper.contains(cohortToken);
    }).toList();
    if (candidates.isEmpty) return null;

    final records = <_Candidate>[];
    for (final code in candidates) {
      final curriculum = await repository.loadCurriculum(code);
      if (curriculum == null) continue;
      records.add(
        _Candidate(
          curriculum: curriculum,
          completeness: curriculum.subjects
              .where((item) => item.code.isNotEmpty)
              .length,
          sourceTime: await _sourceTime(code),
        ),
      );
    }
    if (records.isEmpty) return null;
    final ranking = rankCandidates(
      records.map(
        (item) => CurriculumCandidateSummary(
          code: item.curriculum.code,
          completeness: item.completeness,
          sourceTime: item.sourceTime,
        ),
      ),
    );
    records.sort(
      (a, b) => ranking
          .indexWhere((item) => item.code == a.curriculum.code)
          .compareTo(
            ranking.indexWhere((item) => item.code == b.curriculum.code),
          ),
    );

    Set<String>? common;
    for (final record in records) {
      final codes = record.curriculum.subjects
          .map((item) => item.code.toUpperCase())
          .where((code) => code.isNotEmpty)
          .toSet();
      common = common == null ? codes : common.intersection(codes);
    }
    return ResolvedStudentProfile(
      majorPrefix: student.majorPrefix,
      cohort: student.cohort,
      primaryCurriculum: records.first.curriculum.code,
      candidates: records.map((item) => item.curriculum.code).toList(),
      commonSubjectCodes: (common ?? const <String>{}).toList()..sort(),
    );
  }

  Future<DateTime> _sourceTime(String code) async {
    final json = await repository.loadCurriculumJson(code);
    return DateTime.tryParse(json?['fetchedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static List<CurriculumCandidateSummary> rankCandidates(
    Iterable<CurriculumCandidateSummary> candidates,
  ) {
    final ranked = candidates.toList();
    ranked.sort((a, b) {
      final completeness = b.completeness.compareTo(a.completeness);
      if (completeness != 0) return completeness;
      final time = b.sourceTime.compareTo(a.sourceTime);
      if (time != 0) return time;
      return b.code.compareTo(a.code);
    });
    return ranked;
  }
}

class CurriculumCandidateSummary {
  final String code;
  final int completeness;
  final DateTime sourceTime;

  const CurriculumCandidateSummary({
    required this.code,
    required this.completeness,
    required this.sourceTime,
  });
}

class _Candidate {
  final DatabaseCurriculum curriculum;
  final int completeness;
  final DateTime sourceTime;

  const _Candidate({
    required this.curriculum,
    required this.completeness,
    required this.sourceTime,
  });
}
