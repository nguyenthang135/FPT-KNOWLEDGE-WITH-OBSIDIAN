class CurriculumSubject {
  final String code;
  final String name;
  final int semester;
  final int credits;
  final String prerequisite;

  const CurriculumSubject({
    required this.code,
    required this.name,
    required this.semester,
    required this.credits,
    required this.prerequisite,
  });

  factory CurriculumSubject.fromJson(Map<String, dynamic> json) {
    return CurriculumSubject(
      code: json['code']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      semester: int.tryParse(json['semester']?.toString() ?? '') ?? 0,
      credits: int.tryParse(json['credits']?.toString() ?? '') ?? 0,
      prerequisite: json['prerequisite']?.toString().trim() ?? '',
    );
  }

  bool get hasPrerequisite {
    final value = prerequisite.trim().toLowerCase();

    return value.isNotEmpty && value != 'none' && value != 'không';
  }

  bool get isComboPlaceholder {
    final value = code.trim().toUpperCase();

    return value.contains('_COM*') ||
        value.contains('_COM_') ||
        RegExp(r'_COM\*\d').hasMatch(value);
  }
}
