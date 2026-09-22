import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/flm/curriculum_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CurriculumResolver resolver;

  setUp(() {
    resolver = CurriculumResolver();
  });

  group('CurriculumResolver Search Tests', () {
    test('Searches BIT_SE_JAVA_18D and matches BIT_SE_K18D_19A with Java combo', () async {
      final results = await resolver.search('BIT_SE_JAVA_18D');
      expect(results.isNotEmpty, isTrue);

      final first = results.first;
      expect(first.matchedCode, equals('BIT_SE_K18D_19A'));
      expect(first.baseCode, equals('BIT_SE'));
      expect(first.intakeCode, equals('18D'));
      expect(first.detectedCombo, equals('JAVA'));
      expect(first.explanation, contains('BIT_SE_K18D_19A'));
      expect(first.explanation, contains('JAVA'));
    });

    test('Searches by major code BIT_SE returns multiple SE curricula', () async {
      final results = await resolver.search('BIT_SE');
      expect(results.isNotEmpty, isTrue);
      expect(results.every((r) => r.matchedCode.startsWith('BIT_SE')), isTrue);
    });

    test('Searches by shortcut SE maps to BIT_SE', () async {
      final results = await resolver.search('SE');
      expect(results.isNotEmpty, isTrue);
      expect(results.any((r) => r.matchedCode.startsWith('BIT_SE')), isTrue);
    });

    test('Searches by intake 18D returns matching cohort curricula', () async {
      final results = await resolver.search('18D');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.intakeCode, equals('18D'));
    });

    test('Searches by combo name Java detects combo and does not throw', () async {
      final results = await resolver.search('Java');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.detectedCombo, equals('JAVA'));
    });

    test('Empty search returns all known curricula without error', () async {
      final results = await resolver.search('');
      expect(results.length, greaterThanOrEqualTo(CurriculumResolver.defaultKnownCurricula.length));
    });

    test('Backwards compatible resolve method works correctly', () async {
      final match = await resolver.resolve('BIT_SE_JAVA_18D');
      expect(match, isNotNull);
      expect(match!.matchedCode, equals('BIT_SE_K18D_19A'));
      expect(match.detectedCombo, equals('JAVA'));
      expect(match.intakeCode, equals('18D'));
    });
  });
}
