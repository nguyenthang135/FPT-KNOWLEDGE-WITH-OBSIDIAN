import 'dart:convert';
import 'dart:io';

import '../ai/ask_fpt_models.dart';
import '../flm/flm_combo_service.dart';

class AppSettings {
  AppSettings._() : _settingsDirectory = null;

  AppSettings.forDirectory(Directory directory)
    : _settingsDirectory = directory;

  final Directory? _settingsDirectory;

  static final AppSettings instance = AppSettings._();

  static const int _maxCurriculumHistory = 10;

  Future<String?> getCurrentCurriculum() async {
    final value = (await _read())['currentCurriculum']?.toString().trim();
    return value == null || value.isEmpty ? null : value.toUpperCase();
  }

  Future<void> setCurrentCurriculum(String? curriculumCode) async {
    final data = await _read();
    final code = curriculumCode?.trim().toUpperCase() ?? '';
    if (code.isEmpty) {
      data.remove('currentCurriculum');
    } else {
      data['currentCurriculum'] = code;
      final history = <String>[code];
      final rawHistory = data['curriculumHistory'];
      if (rawHistory is List) {
        history.addAll(
          rawHistory
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty && item.toUpperCase() != code),
        );
      }
      data['curriculumHistory'] = history.take(_maxCurriculumHistory).toList();
    }
    await _write(data);
  }

  Future<Map<String, dynamic>?> getResolvedStudentProfile() async {
    final raw = (await _read())['resolvedStudentProfile'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> setResolvedStudentProfile(Map<String, dynamic>? profile) async {
    final data = await _read();
    if (profile == null) {
      data.remove('resolvedStudentProfile');
    } else {
      data['resolvedStudentProfile'] = profile;
    }
    await _write(data);
  }

  Future<int?> getCurrentSemester() async {
    return int.tryParse((await _read())['currentSemester']?.toString() ?? '');
  }

  Future<void> setCurrentSemester(int? semester) async {
    final data = await _read();
    if (semester == null || semester < 0) {
      data.remove('currentSemester');
    } else {
      data['currentSemester'] = semester;
    }
    await _write(data);
  }

  Future<ActiveContextProvenance> getActiveContextProvenance() async {
    final value = (await _read())['activeContextProvenance']?.toString();
    return ActiveContextProvenance.values.where((item) {
          return item.name == value;
        }).firstOrNull ??
        ActiveContextProvenance.none;
  }

  Future<void> setActiveContextProvenance(
    ActiveContextProvenance provenance,
  ) async {
    final data = await _read();
    data['activeContextProvenance'] = provenance.name;
    await _write(data);
  }

  Future<Map<String, dynamic>?> getAskFptSession() async {
    final raw = (await _read())['askFptSession'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> setAskFptSession(Map<String, dynamic> session) async {
    final data = await _read();
    data['askFptSession'] = session;
    await _write(data);
  }

  Future<void> clearAskFptSession() async {
    final data = await _read();
    data.remove('askFptSession');
    await _write(data);
  }

  Future<SpecializationCombo?> getSpecialization(String curriculumCode) async {
    final data = await _read();
    final code = _canonicalCurriculumCode(curriculumCode);
    final rawProvenance = data['specializationProvenanceByCurriculum'];
    final provenanceName = rawProvenance is Map
        ? rawProvenance[code]?.toString()
        : null;
    final provenance = SpecializationProvenance.values.where((item) {
      return item.name == provenanceName;
    }).firstOrNull;
    if (provenance == null || provenance == SpecializationProvenance.none) {
      // Phase 3.4 stored specialization data without proof that the user made
      // an explicit choice. Do not trust that legacy state.
      final saved = data['specializationsByCurriculum'];
      if (saved is Map && saved.containsKey(code)) {
        final migrated = Map<String, dynamic>.from(saved)..remove(code);
        data['specializationsByCurriculum'] = migrated;
        await _write(data);
      }
      return null;
    }
    final saved = data['specializationsByCurriculum'];

    if (saved is! Map) {
      return null;
    }

    final raw = saved[code];
    if (raw is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(raw);
    final name = map['name']?.toString().trim() ?? '';
    final rawSubjects = map['subjects'];

    if (name.isEmpty || rawSubjects is! List) {
      return null;
    }

    final subjects = rawSubjects
        .whereType<Map>()
        .map((item) => ComboSubject.fromJson(Map<String, dynamic>.from(item)))
        .where((subject) => subject.code.isNotEmpty && subject.semester > 0)
        .toList();

    if (subjects.isEmpty) {
      return null;
    }

    return SpecializationCombo(
      name: name,
      note: map['note']?.toString().trim() ?? '',
      detailUrl: map['detailUrl']?.toString().trim() ?? '',
      subjects: subjects,
    );
  }

  Future<void> setSpecialization(
    String curriculumCode,
    SpecializationCombo specialization, {
    SpecializationProvenance provenance =
        SpecializationProvenance.explicitUserSelection,
  }) async {
    final data = await _read();
    final existing = data['specializationsByCurriculum'];
    final saved = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};

    final code = _canonicalCurriculumCode(curriculumCode);
    saved[code] = {
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
    };

    data['specializationsByCurriculum'] = saved;
    final rawProvenance = data['specializationProvenanceByCurriculum'];
    final provenances = rawProvenance is Map
        ? Map<String, dynamic>.from(rawProvenance)
        : <String, dynamic>{};
    provenances[code] = provenance.name;
    data['specializationProvenanceByCurriculum'] = provenances;
    await _write(data);
  }

  Future<SpecializationProvenance> getSpecializationProvenance(
    String curriculumCode,
  ) async {
    final data = await _read();
    final raw = data['specializationProvenanceByCurriculum'];
    final value = raw is Map
        ? raw[_canonicalCurriculumCode(curriculumCode)]?.toString()
        : null;
    return SpecializationProvenance.values.where((item) {
          return item.name == value;
        }).firstOrNull ??
        SpecializationProvenance.none;
  }

  Future<void> markSpecializationRestored(String curriculumCode) async {
    final data = await _read();
    final code = _canonicalCurriculumCode(curriculumCode);
    final raw = data['specializationProvenanceByCurriculum'];
    final provenances = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    if (provenances[code] ==
        SpecializationProvenance.explicitUserSelection.name) {
      provenances[code] =
          SpecializationProvenance.restoredExplicitSelection.name;
      data['specializationProvenanceByCurriculum'] = provenances;
      await _write(data);
    }
  }

  Future<void> clearSpecialization(String curriculumCode) async {
    final data = await _read();
    final code = _canonicalCurriculumCode(curriculumCode);
    final rawSaved = data['specializationsByCurriculum'];
    final saved = rawSaved is Map
        ? Map<String, dynamic>.from(rawSaved)
        : <String, dynamic>{};
    saved.remove(code);
    data['specializationsByCurriculum'] = saved;
    final rawProvenance = data['specializationProvenanceByCurriculum'];
    final provenances = rawProvenance is Map
        ? Map<String, dynamic>.from(rawProvenance)
        : <String, dynamic>{};
    provenances[code] = SpecializationProvenance.none.name;
    data['specializationProvenanceByCurriculum'] = provenances;
    await _write(data);
  }

  String _canonicalCurriculumCode(String curriculumCode) {
    return curriculumCode.trim().toUpperCase();
  }

  Future<bool> getKeepMeSignedIn() async {
    final data = await _read();

    return data['keepMeSignedIn'] == true;
  }

  Future<void> setKeepMeSignedIn(bool value) async {
    final data = await _read();

    data['keepMeSignedIn'] = value;

    await _write(data);
  }

  Future<List<String>> getCurriculumHistory() async {
    final data = await _read();

    final raw = data['curriculumHistory'];

    if (raw is! List) {
      return [];
    }

    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> addCurriculum(String curriculumCode) async {
    final code = curriculumCode.trim().toUpperCase();

    if (code.isEmpty) {
      return;
    }

    final data = await _read();

    final history = <String>[];

    final raw = data['curriculumHistory'];

    if (raw is List) {
      for (final item in raw) {
        final existing = item.toString().trim();

        if (existing.isEmpty) {
          continue;
        }

        if (existing.toUpperCase() == code) {
          continue;
        }

        history.add(existing);
      }
    }

    // Newest curriculum first.
    history.insert(0, code);

    if (history.length > _maxCurriculumHistory) {
      history.removeRange(_maxCurriculumHistory, history.length);
    }

    data['curriculumHistory'] = history;

    await _write(data);
  }

  Future<void> removeCurriculum(String curriculumCode) async {
    final code = curriculumCode.trim().toUpperCase();

    final data = await _read();

    final raw = data['curriculumHistory'];

    final history = raw is List
        ? raw
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty && item.toUpperCase() != code)
              .toList()
        : <String>[];

    data['curriculumHistory'] = history;

    final current = data['currentCurriculum']?.toString().trim().toUpperCase();
    if (current == code) {
      data.remove('currentCurriculum');
      data['activeContextProvenance'] = ActiveContextProvenance.none.name;
    }

    await _write(data);
  }

  Future<File> _settingsFile() async {
    if (_settingsDirectory != null) {
      if (!await _settingsDirectory.exists()) {
        await _settingsDirectory.create(recursive: true);
      }

      return File(
        '${_settingsDirectory.path}'
        '${Platform.pathSeparator}'
        'app_settings.json',
      );
    }

    final appData = Platform.environment['APPDATA'] ?? Directory.current.path;

    final directory = Directory(
      '$appData'
      '${Platform.pathSeparator}'
      'FPT Knowledge',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return File(
      '${directory.path}'
      '${Platform.pathSeparator}'
      'app_settings.json',
    );
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _settingsFile();

      if (!await file.exists()) {
        return {};
      }

      final content = await file.readAsString();

      if (content.trim().isEmpty) {
        return {};
      }

      final decoded = jsonDecode(content);

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Invalid settings should never stop app startup.
    }

    return {};
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final file = await _settingsFile();

    final json = const JsonEncoder.withIndent('  ').convert(data);

    await file.writeAsString(json, flush: true);
  }
}
