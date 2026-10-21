import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/database/bundled_database_installer.dart';
import 'package:fptu_se_brain/database/database_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const path = String.fromEnvironment('FPT_SMOKE_DATABASE_PATH');
  test(
    'packaged app installed real data into a fresh isolated AppData directory',
    () async {
      final root = Directory(path);
      final validation = await BundledDatabaseInstaller(
        databaseDirectory: root,
      ).validate(root);
      expect(validation.valid, true, reason: validation.error);
      final repository = DatabaseRepository(root);
      await repository.initialize();
      expect(repository.curriculumCount, 490);
      expect(repository.subjectCount, 1313);
      for (final code in ['CEA201', 'PRM393']) {
        expect(await repository.loadSubject(code), isNotNull);
        expect(await repository.search(code), isNotEmpty);
      }
      final marker =
          jsonDecode(await File('$path/.installation.json').readAsString())
              as Map;
      expect(marker['databaseVersion'], 1);
      expect(marker['bundleSha256'], isNotEmpty);
    },
    skip: path.isEmpty
        ? 'Supply the isolated packaged-app database path for runtime smoke verification'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
