import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/flm/flm_combo_service.dart';
import 'package:fptu_se_brain/settings/app_settings.dart';

void main() {
  late Directory temporaryDirectory;
  late AppSettings settings;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'fpt_knowledge_settings_test_',
    );
    settings = AppSettings.forDirectory(temporaryDirectory);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists specialization per canonical curriculum code', () async {
    const specialization = SpecializationCombo(
      name: 'Intensive Java',
      note: 'Backend path',
      detailUrl: 'https://example.test/combo',
      subjects: [
        ComboSubject(code: 'HSF302', name: 'Hibernate', semester: 5),
        ComboSubject(code: 'SBA301', name: 'Spring Boot', semester: 7),
      ],
    );

    await settings.setSpecialization(' bit_se_k18d_19a ', specialization);

    final restored = await settings.getSpecialization('BIT_SE_K18D_19A');

    expect(restored, isNotNull);
    expect(restored!.name, 'Intensive Java');
    expect(restored.subjects.map((subject) => subject.code), [
      'HSF302',
      'SBA301',
    ]);
    expect(restored.subjects.last.semester, 7);
  });

  test('keeps specializations independent between curricula', () async {
    const specialization = SpecializationCombo(
      name: 'Intensive Java',
      note: '',
      detailUrl: '',
      subjects: [ComboSubject(code: 'HSF302', name: 'Hibernate', semester: 5)],
    );

    await settings.setSpecialization('BIT_SE_K18D_19A', specialization);

    expect(await settings.getSpecialization('OTHER_CURRICULUM'), isNull);
  });

  test('persists current curriculum and keeps canonical history', () async {
    await settings.addCurriculum('OLDER_CURRICULUM');
    await settings.setCurrentCurriculum(' bit_se_k18d_19a ');

    expect(await settings.getCurrentCurriculum(), 'BIT_SE_K18D_19A');
    expect(await settings.getCurriculumHistory(), [
      'BIT_SE_K18D_19A',
      'OLDER_CURRICULUM',
    ]);

    await settings.setCurrentCurriculum(null);
    expect(await settings.getCurrentCurriculum(), isNull);
  });

  test(
    'switching and removing saved curricula preserves the library',
    () async {
      await settings.setCurrentCurriculum('CURRICULUM_A');
      await settings.setCurrentCurriculum('CURRICULUM_B');

      expect(await settings.getCurrentCurriculum(), 'CURRICULUM_B');
      expect(
        await settings.getCurriculumHistory(),
        containsAll(['CURRICULUM_A', 'CURRICULUM_B']),
      );

      await settings.setCurrentCurriculum('CURRICULUM_A');
      expect(await settings.getCurrentCurriculum(), 'CURRICULUM_A');
      expect(await settings.getCurriculumHistory(), contains('CURRICULUM_B'));

      await settings.removeCurriculum('CURRICULUM_A');
      expect(await settings.getCurrentCurriculum(), isNull);
      expect(await settings.getCurriculumHistory(), ['CURRICULUM_B']);
    },
  );
}
