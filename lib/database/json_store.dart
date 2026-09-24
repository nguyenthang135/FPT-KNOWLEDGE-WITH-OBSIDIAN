import 'dart:convert';
import 'dart:io';

class JsonStore {
  final Directory root;

  JsonStore({Directory? root})
    : root =
          root ??
          Directory(
            '${Platform.environment['APPDATA'] ?? Directory.current.path}'
            '${Platform.pathSeparator}FPT Knowledge'
            '${Platform.pathSeparator}Database',
          );

  Future<void> initialize() async {
    for (final path in [
      root.path,
      directoryPath('curricula'),
      directoryPath('subjects'),
      directoryPath('specializations'),
      directoryPath('logs'),
    ]) {
      await Directory(path).create(recursive: true);
    }
  }

  String directoryPath(String name) =>
      '${root.path}${Platform.pathSeparator}$name';

  String recordPath(String directory, String code) =>
      '${directoryPath(directory)}${Platform.pathSeparator}${safeName(code)}.json';

  Future<void> writeRecord(
    String directory,
    String code,
    Map<String, dynamic> json,
  ) => writeJson(recordPath(directory, code), json);

  Future<void> writeRoot(String filename, Map<String, dynamic> json) =>
      writeJson('${root.path}${Platform.pathSeparator}$filename', json);

  Future<void> writeLog(String filename, Map<String, dynamic> json) =>
      writeJson(
        '${directoryPath('logs')}${Platform.pathSeparator}$filename',
        json,
      );

  Future<Map<String, dynamic>?> readLog(String filename) =>
      readJson('${directoryPath('logs')}${Platform.pathSeparator}$filename');

  Future<Map<String, dynamic>?> readRoot(String filename) =>
      readJson('${root.path}${Platform.pathSeparator}$filename');

  Future<Map<String, dynamic>?> readJson(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> readRecords(String directory) async {
    final result = <Map<String, dynamic>>[];
    final folder = Directory(directoryPath(directory));
    if (!await folder.exists()) {
      return result;
    }

    await for (final entity in folder.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
        final json = await readJson(entity.path);
        if (json != null) {
          result.add(json);
        }
      }
    }
    return result;
  }

  Future<void> writeJson(String path, Map<String, dynamic> json) async {
    await initialize();
    final finalFile = File(path);
    final temporaryFile = File('$path.tmp');
    final backupFile = File('$path.bak');
    final content = const JsonEncoder.withIndent('  ').convert(json);

    await temporaryFile.writeAsString(content, flush: true);

    try {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      if (await finalFile.exists()) {
        await finalFile.rename(backupFile.path);
      }
      await temporaryFile.rename(finalFile.path);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (!await finalFile.exists() && await backupFile.exists()) {
        await backupFile.rename(finalFile.path);
      }
      rethrow;
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  String safeName(String value) {
    final sanitized = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return sanitized.isEmpty ? 'UNKNOWN' : sanitized;
  }
}
