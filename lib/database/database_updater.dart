import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'bundled_database_installer.dart';
import 'database_integrity.dart';

enum DataUpdateStatus {
  disabled,
  checking,
  upToDate,
  available,
  updating,
  updated,
  offline,
  error,
}

class DataUpdateResponse {
  final int status;
  final List<int> bytes;
  final String? etag;
  const DataUpdateResponse(this.status, this.bytes, {this.etag});
}

typedef DataUpdateTransport =
    Future<DataUpdateResponse> Function(Uri uri, String? etag, int maxBytes);

class DatabaseUpdater extends ChangeNotifier {
  final Directory root;
  final String feedUrl;
  final DataUpdateTransport _transport;
  final DateTime Function() _now;
  DataUpdateStatus status = DataUpdateStatus.disabled;
  String? detail;
  int downloadedBytes = 0;
  int completedRequests = 0;
  bool _busy = false;
  bool _disposed = false;

  DatabaseUpdater(
    this.root, {
    this.feedUrl = const String.fromEnvironment('FPT_DATA_UPDATE_URL'),
    DataUpdateTransport? transport,
    DateTime Function()? now,
  }) : _transport = transport ?? _download,
       _now = now ?? DateTime.now;

  String get label => switch (status) {
    DataUpdateStatus.disabled => 'Data updates not published',
    DataUpdateStatus.checking => 'Checking data updates',
    DataUpdateStatus.upToDate => 'Up to date',
    DataUpdateStatus.available => 'Update available',
    DataUpdateStatus.updating => 'Updating changed records',
    DataUpdateStatus.updated => 'Updated',
    DataUpdateStatus.offline => 'Offline — local data available',
    DataUpdateStatus.error => 'Data update failed — local data preserved',
  };

  File get _cache => File('${root.parent.path}/database_update_state.json');

  void _set(DataUpdateStatus value, [String? message]) {
    status = value;
    detail = message;
    if (!_disposed) notifyListeners();
  }

  Future<bool> check({bool force = false}) async {
    if (_busy || _disposed) return false;
    if (feedUrl.isEmpty) {
      _set(DataUpdateStatus.disabled);
      return false;
    }
    _busy = true;
    try {
      final uri = Uri.parse(feedUrl);
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          uri.host == 'localhost' ||
          InternetAddress.tryParse(uri.host) != null) {
        throw const FormatException('Data feed must use public HTTPS');
      }
      Map cache = {};
      if (await _cache.exists()) {
        try {
          cache = jsonDecode(await _cache.readAsString()) as Map;
        } catch (_) {
          /* Retry broken cache. */
        }
      }
      if (cache['url'] != feedUrl) cache = {};
      final checked = DateTime.tryParse(cache['checkedAt']?.toString() ?? '');
      if (!force &&
          checked != null &&
          !_now().isBefore(checked) &&
          _now().difference(checked) < const Duration(hours: 24)) {
        _set(
          cache['available'] == true
              ? DataUpdateStatus.available
              : DataUpdateStatus.upToDate,
        );
        return false;
      }
      _set(DataUpdateStatus.checking);
      final response = await _transport(
        uri,
        cache['etag']?.toString(),
        1024 * 1024,
      ).timeout(const Duration(seconds: 8));
      downloadedBytes += response.bytes.length;
      completedRequests++;
      if (response.status == 304) {
        if (cache.isEmpty) {
          throw const FormatException('Unexpected not-modified response');
        }
        await _saveCache({
          ...cache,
          'checkedAt': _now().toUtc().toIso8601String(),
        });
        _set(
          cache['available'] == true
              ? DataUpdateStatus.available
              : DataUpdateStatus.upToDate,
        );
        return false;
      }
      if (response.status != 200) {
        throw const HttpException('Data feed unavailable');
      }
      final manifest = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bytes)) as Map,
      );
      final local =
          jsonDecode(
                await File('${root.path}/release_metadata.json').readAsString(),
              )
              as Map;
      final version = manifest['databaseVersion'];
      if (manifest['schemaVersion'] != 1 ||
          version is! int ||
          manifest['maxAppMajor'] != 1 ||
          !_supportedMinimum(manifest['minAppVersion'])) {
        throw const FormatException(
          'Incompatible data update; app upgrade required',
        );
      }
      final newer = version > (local['databaseVersion'] as int);
      final nextCache = {
        'url': feedUrl,
        'checkedAt': _now().toUtc().toIso8601String(),
        'etag': response.etag,
        'available': newer,
      };
      if (!newer) {
        await _saveCache(nextCache);
        _set(DataUpdateStatus.upToDate);
        return false;
      }
      _set(DataUpdateStatus.available);
      if (manifest['baseVersion'] != local['databaseVersion']) {
        // Keep checking later. Never download an unapproved full snapshot.
        _set(
          DataUpdateStatus.available,
          'A compatible delta is unavailable. An app update is required.',
        );
        return false;
      }
      final delta = manifest['delta'] as Map;
      final deltaUri = uri.resolve(delta['url'].toString());
      if (deltaUri.scheme != 'https' ||
          deltaUri.origin != uri.origin ||
          deltaUri.userInfo.isNotEmpty ||
          deltaUri.hasFragment ||
          delta['size'] is! int ||
          (delta['size'] as int) < 1 ||
          (delta['size'] as int) > 32 * 1024 * 1024 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(delta['sha256'].toString())) {
        throw const FormatException('Invalid delta URL, size or checksum');
      }
      _set(DataUpdateStatus.updating);
      final downloaded = await _transport(
        deltaUri,
        null,
        delta['size'] as int,
      ).timeout(const Duration(seconds: 30));
      downloadedBytes += downloaded.bytes.length;
      completedRequests++;
      if (downloaded.status != 200 ||
          downloaded.bytes.length != delta['size'] ||
          databaseHash(downloaded.bytes) != delta['sha256']) {
        throw const FormatException('Delta checksum mismatch');
      }
      await _apply(manifest, downloaded.bytes);
      await _saveCache({...nextCache, 'available': false, 'etag': null});
      _set(DataUpdateStatus.updated);
      return true;
    } on SocketException {
      _set(DataUpdateStatus.offline);
    } on TimeoutException {
      _set(DataUpdateStatus.offline);
    } on HandshakeException {
      _set(DataUpdateStatus.offline);
    } catch (error) {
      _set(
        DataUpdateStatus.error,
        error is FormatException
            ? error.message.toString()
            : 'Update unavailable. Try again later.',
      );
    } finally {
      _busy = false;
    }
    return false;
  }

  static bool _supportedMinimum(Object? raw) {
    final parts = raw?.toString().split('.').map(int.tryParse).toList();
    if (parts == null || parts.length != 3 || parts.any((v) => v == null)) {
      return false;
    }
    const current = [1, 0, 1];
    for (var i = 0; i < 3; i++) {
      if (parts[i]! != current[i]) return parts[i]! < current[i];
    }
    return true;
  }

  Future<void> _saveCache(Map value) async {
    await _cache.parent.create(recursive: true);
    await _cache.writeAsString(jsonEncode(value), flush: true);
  }

  Future<void> _apply(Map<String, dynamic> manifest, List<int> bytes) async {
    final changed = Map<String, dynamic>.from(manifest['changed'] as Map);
    if (manifest['managedManifest'] != null) {
      changed['managed_manifest.json'] = manifest['managedManifest'];
    }
    final removed = (manifest['removed'] as List).cast<String>();
    final localManaged =
        jsonDecode(
              await File('${root.path}/managed_manifest.json').readAsString(),
            )
            as Map;
    final managed = (localManaged['files'] as Map).keys.cast<String>().toSet()
      ..add('managed_manifest.json');
    if (changed.isEmpty ||
        changed.keys.any((path) => !isManagedDatabasePath(path)) ||
        removed.any(
          (path) =>
              !isManagedDatabasePath(path) ||
              !managed.contains(path) ||
              changed.containsKey(path),
        )) {
      throw const FormatException('Invalid managed update paths');
    }
    final stage = Directory('${root.path}.updating');
    final backup = Directory('${root.path}.backup');
    final journal = File('${root.parent.path}/database_update_journal.json');
    if (await stage.exists()) await stage.delete(recursive: true);
    await stage.create();
    try {
      await journal.writeAsString(
        jsonEncode({
          'baseVersion': manifest['baseVersion'],
          'databaseVersion': manifest['databaseVersion'],
          'phase': 'staging',
        }),
        flush: true,
      );
      for (final path in managed) {
        if (!isManagedDatabasePath(path)) {
          throw const FormatException('Unsafe local manifest');
        }
        final source = File('${root.path}/$path');
        if (await FileSystemEntity.type(source.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const FormatException('Missing local managed file');
        }
        final target = File('${stage.path}/$path');
        await target.parent.create(recursive: true);
        await source.copy(target.path);
      }
      final seen = <String>{};
      var expanded = 0;
      for (final file in ZipDecoder().decodeBytes(bytes, verify: true).files) {
        if (!file.isFile) continue;
        final path = file.name;
        expanded += file.size;
        if (!isManagedDatabasePath(path) ||
            file.isSymbolicLink ||
            !seen.add(path.toLowerCase()) ||
            !changed.containsKey(path) ||
            expanded > 250 * 1024 * 1024) {
          throw const FormatException('Unsafe delta archive');
        }
        final expected = changed[path] as Map;
        final content = file.content;
        if (content.length != expected['size'] ||
            databaseHash(content) != expected['sha256']) {
          throw const FormatException('Changed file checksum mismatch');
        }
        final target = File('${stage.path}/$path');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(content, flush: true);
      }
      if (seen.length != changed.length) {
        throw const FormatException('Incomplete delta archive');
      }
      for (final path in removed) {
        final target = File('${stage.path}/$path');
        if (await target.exists()) await target.delete();
      }
      final installer = BundledDatabaseInstaller(databaseDirectory: root);
      final valid = await installer.validate(stage);
      if (!valid.valid ||
          valid.metadata?['databaseVersion'] != manifest['databaseVersion']) {
        throw const FormatException('Updated database failed validation');
      }
      await BundledDatabaseInstaller.writeInstallationMarker(stage, null);
      if (await backup.exists()) await backup.delete(recursive: true);
      await root.rename(backup.path);
      try {
        await stage.rename(root.path);
      } catch (_) {
        await backup.rename(root.path);
        rethrow;
      }
      await backup.delete(recursive: true);
      await journal.delete();
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  static Future<DataUpdateResponse> _download(
    Uri uri,
    String? etag,
    int maxBytes,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects =
          false; // No redirect to a different trust origin.
      if (etag != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const FormatException('Update exceeds advertised size');
        }
        bytes.addAll(chunk);
      }
      return DataUpdateResponse(
        response.statusCode,
        bytes,
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
