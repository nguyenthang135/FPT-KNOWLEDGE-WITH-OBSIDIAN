import 'dart:convert';
import 'dart:io';

class AppSettings {
  AppSettings._();

  static final AppSettings instance =
      AppSettings._();

  static const int _maxCurriculumHistory = 10;

  Future<bool> getKeepMeSignedIn() async {
    final data = await _read();

    return data['keepMeSignedIn'] == true;
  }

  Future<void> setKeepMeSignedIn(
    bool value,
  ) async {
    final data = await _read();

    data['keepMeSignedIn'] = value;

    await _write(data);
  }

  Future<List<String>>
      getCurriculumHistory() async {
    final data = await _read();

    final raw =
        data['curriculumHistory'];

    if (raw is! List) {
      return [];
    }

    return raw
        .map(
          (item) =>
              item.toString().trim(),
        )
        .where(
          (item) =>
              item.isNotEmpty,
        )
        .toList();
  }

  Future<void> addCurriculum(
    String curriculumCode,
  ) async {
    final code =
        curriculumCode
            .trim()
            .toUpperCase();

    if (code.isEmpty) {
      return;
    }

    final data = await _read();

    final history =
        <String>[];

    final raw =
        data['curriculumHistory'];

    if (raw is List) {
      for (final item in raw) {
        final existing =
            item.toString().trim();

        if (existing.isEmpty) {
          continue;
        }

        if (existing.toUpperCase() ==
            code) {
          continue;
        }

        history.add(existing);
      }
    }

    // Newest curriculum first.
    history.insert(
      0,
      code,
    );

    if (history.length >
        _maxCurriculumHistory) {
      history.removeRange(
        _maxCurriculumHistory,
        history.length,
      );
    }

    data['curriculumHistory'] =
        history;

    await _write(data);
  }

  Future<void> removeCurriculum(
    String curriculumCode,
  ) async {
    final code =
        curriculumCode
            .trim()
            .toUpperCase();

    final data = await _read();

    final raw =
        data['curriculumHistory'];

    if (raw is! List) {
      return;
    }

    final history =
        raw
            .map(
              (item) =>
                  item.toString().trim(),
            )
            .where(
              (item) =>
                  item.isNotEmpty &&
                  item.toUpperCase() !=
                      code,
            )
            .toList();

    data['curriculumHistory'] =
        history;

    await _write(data);
  }

  Future<File> _settingsFile() async {
    final appData =
        Platform.environment[
                'APPDATA'] ??
            Directory.current.path;

    final directory =
        Directory(
      '$appData'
      '${Platform.pathSeparator}'
      'FPT Knowledge',
    );

    if (!await directory.exists()) {
      await directory.create(
        recursive: true,
      );
    }

    return File(
      '${directory.path}'
      '${Platform.pathSeparator}'
      'app_settings.json',
    );
  }

  Future<Map<String, dynamic>>
      _read() async {
    try {
      final file =
          await _settingsFile();

      if (!await file.exists()) {
        return {};
      }

      final content =
          await file.readAsString();

      if (content.trim().isEmpty) {
        return {};
      }

      final decoded =
          jsonDecode(content);

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (_) {
      // Invalid settings should never stop app startup.
    }

    return {};
  }

  Future<void> _write(
    Map<String, dynamic> data,
  ) async {
    final file =
        await _settingsFile();

    final json =
        const JsonEncoder.withIndent(
          '  ',
        ).convert(data);

    await file.writeAsString(
      json,
      flush: true,
    );
  }
}