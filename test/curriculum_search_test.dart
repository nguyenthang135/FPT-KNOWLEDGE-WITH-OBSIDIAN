import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/models/curriculum_subject.dart';
import 'package:fptu_se_brain/search/curriculum_search.dart';

void main() {
  const subject = CurriculumSubject(
    code: 'CEA201',
    name: 'Computer Architecture',
    semester: 5,
    credits: 3,
    prerequisite: '',
  );

  test('matches semester aliases', () {
    expect(semesterMatchesCurriculumQuery(5, 'semester 5'), isTrue);
    expect(semesterMatchesCurriculumQuery(5, ' sem 5 '), isTrue);
    expect(semesterMatchesCurriculumQuery(5, '5'), isTrue);
    expect(semesterMatchesCurriculumQuery(1, 'semester 5'), isFalse);
  });

  test('matches preparation semester', () {
    expect(semesterMatchesCurriculumQuery(0, 'Preparation'), isTrue);
    expect(semesterMatchesCurriculumQuery(0, 'semester 0'), isTrue);
  });

  test('matches subject code and name case-insensitively', () {
    expect(curriculumSubjectMatchesQuery(subject, 'cea201'), isTrue);
    expect(
      curriculumSubjectMatchesQuery(subject, 'COMPUTER ARCHITECTURE'),
      isTrue,
    );
    expect(curriculumSubjectMatchesQuery(subject, 'project'), isFalse);
  });

  test('normalizes Vietnamese diacritics', () {
    const vietnameseSubject = CurriculumSubject(
      code: 'VOV101',
      name: 'Vovinam Việt Võ Đạo',
      semester: 1,
      credits: 2,
      prerequisite: '',
    );

    expect(
      curriculumSubjectMatchesQuery(vietnameseSubject, 'viet vo dao'),
      isTrue,
    );
  });
}
