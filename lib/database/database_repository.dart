import 'dart:convert';
import 'dart:io';

import '../flm/flm_combo_service.dart';
import '../search/curriculum_search.dart';

class DatabaseCurriculumSubject {
  final String code;
  final String name;
  final int semester;
  final int credits;
  final String prerequisite;
  final bool isComboPlaceholder;

  const DatabaseCurriculumSubject({
    required this.code,
    required this.name,
    required this.semester,
    required this.credits,
    required this.prerequisite,
    required this.isComboPlaceholder,
  });
}

class DatabaseCurriculum {
  final String code;
  final String name;
  final int? totalCredits;
  final List<DatabaseCurriculumSubject> subjects;

  const DatabaseCurriculum({
    required this.code,
    required this.name,
    required this.totalCredits,
    required this.subjects,
  });
}

class DatabaseSearchResult {
  final String type;
  final String code;
  final String name;
  final String searchableText;

  const DatabaseSearchResult({
    required this.type,
    required this.code,
    required this.name,
    required this.searchableText,
  });
}

class DatabaseRepository {
  final Directory root;

  Map<String, dynamic>? _index;
  List<DatabaseSearchResult>? _searchIndex;
  Future<List<DatabaseSearchResult>>? _searchIndexFuture;

  DatabaseRepository(this.root);

  Map<String, dynamic> get index => _index ?? const {};
  int get curriculumCount => _int(index['curriculumCount']);
  int get subjectCount => _int(index['subjectCount']);
  int get syllabusCount => _int(index['syllabusCount']);
  int get specializationCurriculumCount =>
      _int(index['specializationCurriculumCount']);
  List<String> get curriculumCodes => index['curricula'] is List
      ? (index['curricula'] as List).map((item) => item.toString()).toList()
      : const [];

  Future<void> initialize() async {
    _index = await _readObject(
      File('${root.path}${Platform.pathSeparator}database_index.json'),
    );
  }

  Future<bool> containsCurriculum(String code) async {
    return File(_recordPath('curricula', code)).exists();
  }

  Future<DatabaseCurriculum?> loadCurriculum(String code) async {
    final file = File(_recordPath('curricula', code));
    if (!await file.exists()) return null;
    final json = await _readObject(file);
    final subjects = <DatabaseCurriculumSubject>[];
    final semesters = json['semesters'];
    if (semesters is List) {
      for (final rawSemester in semesters.whereType<Map>()) {
        final semester = _int(rawSemester['semester']);
        final rawSubjects = rawSemester['subjects'];
        if (rawSubjects is! List) continue;
        for (final raw in rawSubjects.whereType<Map>()) {
          final item = Map<String, dynamic>.from(raw);
          subjects.add(
            DatabaseCurriculumSubject(
              code: item['code']?.toString().trim() ?? '',
              name: item['name']?.toString().trim() ?? '',
              semester: semester,
              credits: _int(item['credits']),
              prerequisite: item['prerequisite']?.toString().trim() ?? '',
              isComboPlaceholder: item['isComboPlaceholder'] == true,
            ),
          );
        }
      }
    }
    return DatabaseCurriculum(
      code: json['code']?.toString().trim() ?? code.toUpperCase(),
      name: json['name']?.toString().trim() ?? '',
      totalCredits: int.tryParse(json['totalCredits']?.toString() ?? ''),
      subjects: subjects,
    );
  }

  Future<Map<String, dynamic>?> loadCurriculumJson(String code) async {
    final file = File(_recordPath('curricula', code));
    return await file.exists() ? _readObject(file) : null;
  }

  Future<Map<String, dynamic>?> loadSubject(String code) async {
    final file = File(_recordPath('subjects', code));
    return await file.exists() ? _readObject(file) : null;
  }

  Future<List<DatabaseSearchResult>> findSubjectCodes(String reference) async {
    final normalized = reference.trim().toUpperCase();
    if (normalized.isEmpty) return const [];
    final records = await _ensureSearchIndex();
    final subjects = records.where((item) => item.type == 'subject').toList();
    final exact = subjects.where(
      (item) => item.code.toUpperCase() == normalized,
    );
    if (exact.isNotEmpty) return exact.toList();
    return subjects
        .where((item) => item.code.toUpperCase().startsWith(normalized))
        .toList();
  }

  Future<List<SpecializationCombo>> loadSpecializations(String code) async {
    final file = File(_recordPath('specializations', code));
    if (!await file.exists()) return [];
    final json = await _readObject(file);
    final rawValues = json['specializations'];
    if (rawValues is! List) return [];
    return rawValues.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final subjects = item['subjects'] is List
          ? (item['subjects'] as List)
                .whereType<Map>()
                .map(
                  (value) =>
                      ComboSubject.fromJson(Map<String, dynamic>.from(value)),
                )
                .toList()
          : <ComboSubject>[];
      return SpecializationCombo(
        name: item['name']?.toString().trim() ?? '',
        note: item['note']?.toString().trim() ?? '',
        detailUrl: item['detailUrl']?.toString().trim() ?? '',
        subjects: subjects,
      );
    }).toList();
  }

  Future<List<SpecializationCombo>> loadProfessionalSpecializations(
    String code,
  ) async {
    final curriculum = await loadCurriculum(code);
    if (curriculum == null) return const [];
    final major = _curriculumMajor(code);
    if (major == null) return const [];
    final family = '${major}_COM';
    final hasProfessionalSlots = curriculum.subjects.any(
      (subject) =>
          subject.isComboPlaceholder &&
          subject.code.toUpperCase().startsWith(family),
    );
    if (!hasProfessionalSlots) return const [];
    final values = await loadSpecializations(code);
    return values.where((choice) {
      final groupCode = choice.name.split(':').first.trim().toUpperCase();
      if (!groupCode.startsWith(family)) return false;
      if (choice.subjects.length < 2) return false;
      return !_isLanguageTrack(choice);
    }).toList();
  }

  Future<List<DatabaseSearchResult>> search(String query) async {
    final records = await _ensureSearchIndex();
    final normalized = normalizeCurriculumSearchText(query);
    if (normalized.isEmpty) {
      return records
          .where((item) => item.type == 'curriculum')
          .take(80)
          .toList();
    }
    return records
        .where((item) => item.searchableText.contains(normalized))
        .take(200)
        .toList();
  }

  Future<List<DatabaseSearchResult>> _ensureSearchIndex() async {
    if (_searchIndex != null) return _searchIndex!;
    final inProgress = _searchIndexFuture;
    if (inProgress != null) return inProgress;
    final build = _buildSearchIndex();
    _searchIndexFuture = build;
    try {
      return await build;
    } catch (_) {
      if (identical(_searchIndexFuture, build)) {
        _searchIndexFuture = null;
      }
      rethrow;
    }
  }

  Future<List<DatabaseSearchResult>> _buildSearchIndex() async {
    final records = <DatabaseSearchResult>[];
    final curricula = index['curricula'];
    if (curricula is List) {
      for (final value in curricula) {
        final code = value.toString();
        final curriculum = await loadCurriculum(code);
        if (curriculum == null) continue;
        final specializations = await loadSpecializations(code);
        final specializationNames = specializations
            .map((item) => item.name)
            .join(' ');
        final name = curriculum.name.isEmpty ? code : curriculum.name;
        records.add(
          DatabaseSearchResult(
            type: 'curriculum',
            code: code,
            name: name,
            searchableText: normalizeCurriculumSearchText(
              '$code $name $specializationNames',
            ),
          ),
        );
      }
    }

    final subjectDirectory = Directory(
      '${root.path}${Platform.pathSeparator}subjects',
    );
    final files = await subjectDirectory
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    for (final file in files) {
      final json = await _readObject(file);
      final code = json['code']?.toString().trim() ?? '';
      if (code.isEmpty) continue;
      final syllabusName = json['syllabusName']?.toString().trim() ?? '';
      final englishName = json['englishName']?.toString().trim() ?? '';
      final name = syllabusName.isNotEmpty
          ? syllabusName
          : (englishName.isNotEmpty ? englishName : code);
      records.add(
        DatabaseSearchResult(
          type: 'subject',
          code: code,
          name: name,
          searchableText: normalizeCurriculumSearchText(
            '$code $syllabusName $englishName',
          ),
        ),
      );
    }
    records.sort((a, b) {
      final type = a.type.compareTo(b.type);
      return type != 0 ? type : a.code.compareTo(b.code);
    });
    _searchIndex = records;
    return records;
  }

  String _recordPath(String directory, String code) {
    final safe = code
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return '${root.path}${Platform.pathSeparator}$directory'
        '${Platform.pathSeparator}$safe.json';
  }

  static String? _curriculumMajor(String code) {
    final parts = code.trim().toUpperCase().split('_');
    if (parts.length < 2) return null;
    return parts[0] == 'BIT' || parts[0] == 'BBA' ? parts[1] : parts[0];
  }

  static bool _isLanguageTrack(SpecializationCombo choice) {
    if (choice.subjects.isEmpty) return false;
    return choice.subjects.every((subject) {
      final code = subject.code.trim().toUpperCase();
      return _languageTrackPrefixes.any(code.startsWith);
    });
  }

  static const _languageTrackPrefixes = {
    'JPD',
    'JIS',
    'JIT',
    'JFE',
    'JTW',
    'KOR',
    'CHI',
    'CHN',
  };

  Future<Map<String, dynamic>> _readObject(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw FormatException('Expected JSON object in ${file.path}');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static int _int(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
}
