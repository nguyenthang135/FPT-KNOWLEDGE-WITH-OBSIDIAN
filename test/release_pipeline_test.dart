import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/ai/groq_ai_service.dart';
import 'package:fptu_se_brain/database/bundled_database_installer.dart';
import 'package:fptu_se_brain/database/database_integrity.dart';
import 'package:fptu_se_brain/database/database_repository.dart';
import 'package:fptu_se_brain/database/database_updater.dart';

List<int> encode(Object value) => utf8.encode(jsonEncode(value));

Map<String, List<int>> snapshot(int version) {
  final files = <String, List<int>>{
    'database_index.json': encode({
      'curriculumCount': 1,
      'subjectCount': version == 1 ? 1 : 2,
      'curricula': ['TEST'],
    }),
    'release_metadata.json': encode({
      'schemaVersion': 1,
      'databaseVersion': version,
      'builtAt': '2026-10-21T00:00:00Z',
    }),
    'curricula/TEST.json': encode({
      'code': 'TEST',
      'name': 'Test curriculum',
      'semesters': [],
    }),
    'subjects/CEA201.json': encode({
      'code': 'CEA201',
      'englishName': version == 1 ? 'Original' : 'Updated syllabus',
    }),
    if (version > 1)
      'subjects/PRM393.json': encode({
        'code': 'PRM393',
        'englishName': 'Mobile programming',
      }),
    'search_index.json': encode({'records': []}),
  };
  files['managed_manifest.json'] = encode({
    'files': {
      for (final entry in files.entries)
        entry.key: {
          'size': entry.value.length,
          'sha256': databaseHash(entry.value),
        },
    },
  });
  return files;
}

List<int> zip(Map<String, List<int>> files, {String prefix = ''}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile('$prefix${entry.key}', entry.value.length, entry.value),
    );
  }
  return ZipEncoder().encode(archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Directory root;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fpt_release_test_');
    root = Directory('${temporary.path}/Database');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<void> install(Map<String, List<int>> files) async {
    for (final entry in files.entries) {
      final target = File('${root.path}/${entry.key}');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(entry.value);
    }
  }

  test(
    'both AI paths use HTTPS gateway without sending the developer key',
    () async {
      var requests = 0;
      final ai = GroqAiService(
        apiKey: 'test-only',
        gatewayUrl: 'https://gateway.fpt.test/api/ai/chat',
        transport: (uri, headers, body) async {
          requests++;
          expect(uri.host, 'gateway.fpt.test');
          expect(headers.containsKey(HttpHeaders.authorizationHeader), false);
          expect(body, isNot(contains('test-only')));
          return GroqHttpResponse(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"summary":"Tiếng Việt"}'},
                },
              ],
            }),
          );
        },
      );
      expect(
        (await ai.plan(
          question: 'q',
          knownContext: {},
          english: false,
        )).isSuccess,
        true,
      );
      expect(
        (await ai.answer(question: 'q', context: {}, english: false)).isSuccess,
        true,
      );
      expect(requests, 2);
    },
  );

  test(
    'gateway 429 returns immediately and unsafe URLs stay offline',
    () async {
      var requests = 0;
      final ai = GroqAiService(
        gatewayUrl: 'https://gateway.fpt.test/api/ai/chat',
        transport: (_, _, _) async {
          requests++;
          return const GroqHttpResponse(429, '{}');
        },
      );
      expect(
        (await ai.answer(question: 'q', context: {}, english: false)).failure,
        GroqFailureKind.rateLimited,
      );
      expect(requests, 1);
      for (final url in [
        'http://gateway.fpt.test',
        'https://localhost/ai',
        'https://127.0.0.1/ai',
        'https://example.com/ai',
      ]) {
        expect(GroqAiService(gatewayUrl: url).configured, false);
      }
    },
  );

  test(
    'second startup never opens ZIP or scans records; deep diagnostic catches damage',
    () async {
      var loads = 0;
      final files = snapshot(1);
      final bytes = zip(files, prefix: 'Database/');
      final descriptor = {
        ...jsonDecode(utf8.decode(files['release_metadata.json']!)) as Map,
        'databaseSha256': databaseHash(bytes),
      };
      final installer = BundledDatabaseInstaller(
        databaseDirectory: root,
        metadataLoader: () async => Map<String, dynamic>.from(descriptor),
        assetLoader: () async {
          loads++;
          return Uint8List.fromList(bytes);
        },
      );
      await installer.ensureInstalled();
      await File('${root.path}/subjects/CEA201.json').writeAsString('damaged');
      await installer.ensureInstalled();
      expect(loads, 1);
      expect((await installer.validate(root)).valid, false);
    },
  );

  test(
    'ZIP traversal rejected before activation; personal notes preserved',
    () async {
      final files = snapshot(1)..['../notes.txt'] = encode('unsafe');
      final bytes = zip(files, prefix: 'Database/');
      final installer = BundledDatabaseInstaller(
        databaseDirectory: root,
        metadataLoader: () async => {'databaseSha256': databaseHash(bytes)},
        assetLoader: () async => Uint8List.fromList(bytes),
      );
      final notes = File('${temporary.path}/notes.md');
      await notes.writeAsString('personal');
      await expectLater(installer.ensureInstalled(), throwsStateError);
      expect(await notes.readAsString(), 'personal');
      expect(await root.exists(), false);
    },
  );

  test(
    'legacy install gains managed and prebuilt search indexes once',
    () async {
      final files = snapshot(1);
      await install(files);
      await File('${root.path}/search_index.json').delete();
      await File('${root.path}/managed_manifest.json').delete();
      final bytes = zip(files, prefix: 'Database/');
      var loads = 0;
      final descriptor = <String, dynamic>{
        ...jsonDecode(utf8.decode(files['release_metadata.json']!)) as Map,
        'databaseSha256': databaseHash(bytes),
        'managedManifestSha256': databaseHash(files['managed_manifest.json']!),
      };
      final installer = BundledDatabaseInstaller(
        databaseDirectory: root,
        metadataLoader: () async => descriptor,
        assetLoader: () async {
          loads++;
          return Uint8List.fromList(bytes);
        },
      );
      await installer.ensureInstalled();
      await installer.ensureInstalled();
      expect(loads, 1);
      expect(await File('${root.path}/search_index.json').exists(), true);
    },
  );

  test('no-op update uses ETag, TTL, and only tiny manifest request', () async {
    await install(snapshot(1));
    var calls = 0;
    var now = DateTime.utc(2026, 10, 21);
    final updater = DatabaseUpdater(
      root,
      feedUrl: 'https://updates.fpt.test/latest.json',
      now: () => now,
      transport: (_, etag, _) async {
        calls++;
        if (etag != null) {
          expect(etag, 'v1');
          return const DataUpdateResponse(304, []);
        }
        return DataUpdateResponse(
          200,
          encode({
            'databaseVersion': 1,
            'schemaVersion': 1,
            'minAppVersion': '1.0.1',
            'maxAppMajor': 1,
          }),
          etag: 'v1',
        );
      },
    );
    await updater.check();
    await updater.check();
    expect(calls, 1);
    now = now.add(const Duration(hours: 25));
    await updater.check();
    expect(calls, 2);
    expect(updater.status, DataUpdateStatus.upToDate);
  });

  Future<(Map<String, dynamic>, List<int>)> deltaFixture() async {
    final old = snapshot(1);
    final next = snapshot(2);
    await install(old);
    final changed = Map<String, List<int>>.fromEntries(
      next.entries.where(
        (entry) =>
            databaseHash(old[entry.key] ?? []) != databaseHash(entry.value),
      ),
    );
    expect(changed.containsKey('curricula/TEST.json'), false);
    final bytes = zip(changed);
    return (
      {
        'databaseVersion': 2,
        'schemaVersion': 1,
        'baseVersion': 1,
        'minAppVersion': '1.0.1',
        'maxAppMajor': 1,
        'delta': {
          'url': 'v1-v2.zip',
          'size': bytes.length,
          'sha256': databaseHash(bytes),
        },
        'changed': {
          for (final entry in changed.entries)
            entry.key: {
              'size': entry.value.length,
              'sha256': databaseHash(entry.value),
            },
        },
        'removed': [],
      },
      bytes,
    );
  }

  test(
    'real ZIP delta transfers only changed/additional files and preserves notes',
    () async {
      final (manifest, bytes) = await deltaFixture();
      final original = await File(
        '${root.path}/curricula/TEST.json',
      ).readAsBytes();
      final note = File('${temporary.path}/My Notes.md');
      await note.writeAsString('keep');
      var downloads = 0;
      final updater = DatabaseUpdater(
        root,
        feedUrl: 'https://updates.fpt.test/latest.json',
        transport: (uri, _, _) async {
          if (uri.path.endsWith('.json')) {
            return DataUpdateResponse(200, encode(manifest));
          }
          downloads++;
          return DataUpdateResponse(200, bytes);
        },
      );
      expect(await updater.check(), true);
      expect(updater.status, DataUpdateStatus.updated);
      expect(downloads, 1);
      expect(
        await File('${root.path}/curricula/TEST.json').readAsBytes(),
        original,
      );
      expect(await note.readAsString(), 'keep');
      expect(
        (await DatabaseRepository(root).loadSubject('PRM393'))?['englishName'],
        'Mobile programming',
      );
      expect(
        (await BundledDatabaseInstaller(
          databaseDirectory: root,
        ).validate(root)).valid,
        true,
      );
    },
  );

  test(
    'HTTP delta downloads exactly changed payload bytes, no baseline',
    () async {
      final (manifest, deltaBytes) = await deltaFixture();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var payloadRequests = 0;
      var transferredPayloadBytes = 0;
      final subscription = server.listen((request) async {
        final isPayload = request.uri.path.endsWith('.zip');
        final body = isPayload ? deltaBytes : encode(manifest);
        if (isPayload) {
          payloadRequests++;
          transferredPayloadBytes += body.length;
        }
        request.response.headers.contentType = isPayload
            ? ContentType.binary
            : ContentType.json;
        request.response.add(body);
        await request.response.close();
      });
      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousHttpOverrides);
      final client = HttpClient();
      final updater = DatabaseUpdater(
        root,
        feedUrl: 'https://updates.fpt.test/latest.json',
        transport: (uri, etag, maxBytes) async {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}${uri.path}'),
          );
          if (etag != null) {
            request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
          }
          final response = await request.close();
          final bytes = <int>[];
          await for (final chunk in response) {
            bytes.addAll(chunk);
          }
          expect(bytes.length, lessThanOrEqualTo(maxBytes));
          return DataUpdateResponse(response.statusCode, bytes);
        },
      );
      try {
        expect(await updater.check(force: true), true);
        expect(await updater.check(force: true), false);
        expect(payloadRequests, 1);
        expect(transferredPayloadBytes, deltaBytes.length);
        expect(
          updater.downloadedBytes,
          deltaBytes.length + 2 * encode(manifest).length,
        );
        expect(
          deltaBytes.length,
          lessThan(zip(snapshot(2), prefix: 'Database/').length),
        );
        // ignore: avoid_print
        print(
          'Verified HTTP delta payload: ${deltaBytes.length} bytes; baseline not requested.',
        );
      } finally {
        updater.dispose();
        client.close(force: true);
        await server.close(force: true);
        await subscription.cancel();
      }
    },
  );

  test(
    'corrupt download and interrupted activation preserve last-good dataset',
    () async {
      final (manifest, bytes) = await deltaFixture();
      final updater = DatabaseUpdater(
        root,
        feedUrl: 'https://updates.fpt.test/latest.json',
        transport: (uri, _, _) async => DataUpdateResponse(
          200,
          uri.path.endsWith('.json') ? encode(manifest) : [...bytes, 0],
        ),
      );
      expect(await updater.check(), false);
      expect(updater.status, DataUpdateStatus.error);
      expect(await File('${root.path}/subjects/PRM393.json').exists(), false);
      await root.rename('${root.path}.backup');
      await BundledDatabaseInstaller(
        databaseDirectory: root,
      ).recoverInterruptedInstall();
      expect(
        (await DatabaseRepository(root).loadSubject('CEA201'))?['englishName'],
        'Original',
      );
    },
  );

  test('offline update leaves local data immediately available', () async {
    await install(snapshot(1));
    final updater = DatabaseUpdater(
      root,
      feedUrl: 'https://updates.fpt.test/latest.json',
      transport: (_, _, _) async => throw const SocketException('offline'),
    );
    expect(await updater.check(), false);
    expect(updater.status, DataUpdateStatus.offline);
    expect(await File('${root.path}/subjects/CEA201.json').exists(), true);
  });
}
