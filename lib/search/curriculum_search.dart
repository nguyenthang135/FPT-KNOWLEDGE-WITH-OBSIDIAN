import '../flm/flm_combo_service.dart';
import '../models/curriculum_subject.dart';

String normalizeCurriculumSearchText(String value) {
  const replacements = <String, String>{
    'à': 'a',
    'á': 'a',
    'ạ': 'a',
    'ả': 'a',
    'ã': 'a',
    'â': 'a',
    'ầ': 'a',
    'ấ': 'a',
    'ậ': 'a',
    'ẩ': 'a',
    'ẫ': 'a',
    'ă': 'a',
    'ằ': 'a',
    'ắ': 'a',
    'ặ': 'a',
    'ẳ': 'a',
    'ẵ': 'a',
    'è': 'e',
    'é': 'e',
    'ẹ': 'e',
    'ẻ': 'e',
    'ẽ': 'e',
    'ê': 'e',
    'ề': 'e',
    'ế': 'e',
    'ệ': 'e',
    'ể': 'e',
    'ễ': 'e',
    'ì': 'i',
    'í': 'i',
    'ị': 'i',
    'ỉ': 'i',
    'ĩ': 'i',
    'ò': 'o',
    'ó': 'o',
    'ọ': 'o',
    'ỏ': 'o',
    'õ': 'o',
    'ô': 'o',
    'ồ': 'o',
    'ố': 'o',
    'ộ': 'o',
    'ổ': 'o',
    'ỗ': 'o',
    'ơ': 'o',
    'ờ': 'o',
    'ớ': 'o',
    'ợ': 'o',
    'ở': 'o',
    'ỡ': 'o',
    'ù': 'u',
    'ú': 'u',
    'ụ': 'u',
    'ủ': 'u',
    'ũ': 'u',
    'ư': 'u',
    'ừ': 'u',
    'ứ': 'u',
    'ự': 'u',
    'ử': 'u',
    'ữ': 'u',
    'ỳ': 'y',
    'ý': 'y',
    'ỵ': 'y',
    'ỷ': 'y',
    'ỹ': 'y',
    'đ': 'd',
  };

  final normalized = value
      .trim()
      .toLowerCase()
      .split('')
      .map((character) => replacements[character] ?? character)
      .join();

  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

bool semesterMatchesCurriculumQuery(int semester, String query) {
  final normalized = normalizeCurriculumSearchText(query);

  if (normalized.isEmpty) {
    return true;
  }

  final number = semester.toString();
  final aliases = <String>{number, 'semester $number', 'sem $number'};

  if (semester == 0) {
    aliases.addAll({
      'preparation',
      'preparation semester',
      'preparation semester 0',
    });
  }

  return aliases.contains(normalized);
}

bool curriculumSubjectMatchesQuery(CurriculumSubject subject, String query) {
  final normalized = normalizeCurriculumSearchText(query);

  if (normalized.isEmpty) {
    return true;
  }

  return normalizeCurriculumSearchText(
    '${subject.code} ${subject.name}',
  ).contains(normalized);
}

bool comboSubjectMatchesQuery(ComboSubject subject, String query) {
  final normalized = normalizeCurriculumSearchText(query);

  if (normalized.isEmpty) {
    return true;
  }

  return normalizeCurriculumSearchText(
    '${subject.code} ${subject.name}',
  ).contains(normalized);
}
