import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/database/bundled_database_installer.dart';
import 'package:fptu_se_brain/database/database_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late Directory databaseDirectory;

  Future<Uint8List> loadBundle() async {
    final data = await rootBundle.load(BundledDatabaseInstaller.assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'fpt_knowledge_database_test_',
    );
    databaseDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Database',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('installs and validates the bundled real database', () async {
    final installer = BundledDatabaseInstaller(
      databaseDirectory: databaseDirectory,
      assetLoader: loadBundle,
    );

    await installer.ensureInstalled();
    final validation = await installer.validate(databaseDirectory);

    expect(validation.valid, isTrue);
    expect(validation.index?['curriculumCount'], 490);
    expect(validation.index?['subjectCount'], 1313);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('recovers an invalid local database and updates older metadata', () async {
    await databaseDirectory.create(recursive: true);
    await File(
      '${databaseDirectory.path}${Platform.pathSeparator}broken.txt',
    ).writeAsString('keep no partial database');
    final installer = BundledDatabaseInstaller(
      databaseDirectory: databaseDirectory,
      assetLoader: loadBundle,
    );

    await installer.ensureInstalled();
    final metadataFile = File(
      '${databaseDirectory.path}${Platform.pathSeparator}release_metadata.json',
    );
    final metadata = Map<String, dynamic>.from(
      jsonDecode(await metadataFile.readAsString()) as Map,
    );
    metadata['databaseVersion'] = 0;
    await metadataFile.writeAsString(jsonEncode(metadata));

    await installer.ensureInstalled();
    final restored = jsonDecode(await metadataFile.readAsString()) as Map;
    expect(restored['databaseVersion'], 1);
    expect((await installer.validate(databaseDirectory)).valid, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('search and known real records work entirely from JSON', () async {
    final installer = BundledDatabaseInstaller(
      databaseDirectory: databaseDirectory,
      assetLoader: loadBundle,
    );
    await installer.ensureInstalled();
    final repository = DatabaseRepository(databaseDirectory);
    await repository.initialize();

    for (final query in [
      'CEA201',
      'cea201',
      'Computer Organization',
      'kien truc may tinh',
      'BIT_SE_K18D_19A',
      'software engineering',
      'Java',
    ]) {
      expect(await repository.search(query), isNotEmpty, reason: query);
    }

    final curriculum = await repository.loadCurriculum('BIT_SE_K18D_19A');
    expect(curriculum, isNotNull);
    expect(curriculum!.subjects, isNotEmpty);
    expect(curriculum.subjects.any((item) => item.code == 'CEA201'), isTrue);
    expect(await repository.loadSpecializations(curriculum.code), isNotEmpty);

    final subject = await repository.loadSubject('CEA201');
    expect(subject?['englishName'], contains('Computer Organization'));
    expect(subject?['learningOutcomes'], hasLength(10));
    expect(subject?['assessments'], isNotEmpty);
    expect(subject?['learningMaterials'], isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
