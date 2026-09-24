import '../search/curriculum_search.dart';

enum AskFptIntent {
  subjectOverview,
  subjectAssessment,
  subjectPrerequisite,
  subjectMaterials,
  subjectOutcomes,
  subjectCredits,
  semesterSubjects,
  curriculumOverview,
  personalCurriculumSubjects,
  specializationOverview,
  compareSpecializationAndCore,
  futureSemester,
  notesAddSubject,
  notesAddSemester,
  notesAddCurriculum,
  outOfScope,
}

class AskFptIntentResult {
  final AskFptIntent intent;
  final bool personal;
  final bool english;
  final int? semester;
  final int? statedCurrentSemester;

  const AskFptIntentResult({
    required this.intent,
    required this.personal,
    required this.english,
    this.semester,
    this.statedCurrentSemester,
  });
}

class AskFptIntentResolver {
  const AskFptIntentResolver();

  AskFptIntentResult resolve(String question) {
    final text = normalizeCurriculumSearchText(question);
    final english = RegExp(
      r'\b(what|which|does|is|are|course|semester|subject|materials|credits|prerequisite|export|notes)\b',
    ).hasMatch(text);
    final semester = _semester(text);
    final statedCurrentSemester = RegExp(
      r'\b(?:dang hoc ky|current semester|in semester)\s*(\d{1,2})\b',
    ).firstMatch(text);
    final current = statedCurrentSemester == null
        ? null
        : int.tryParse(statedCurrentSemester.group(1)!);
    final export =
        RegExp(
          r'\b(them|luu|xuat|add|save|export|tao|can|need)\b',
        ).hasMatch(text) &&
        RegExp(
          r'\b(ghi chu|note|notes|obsidian|markdown|curriculum|hoc ky|semester)\b',
        ).hasMatch(text);
    final hasExplicitSubjectCode = RegExp(
      r'\b[a-z]{2,6}\d{2,4}[a-z]?\b',
    ).hasMatch(text);
    final personalPronoun = RegExp(
      r'\b(toi|minh|cua toi|cua minh|my|i)\b',
    ).hasMatch(text);
    final asksAboutProgramSubjects =
        RegExp(
          r'\b(nhung mon|cac mon|mon nao|hoc nhung gi|toi hoc gi|subjects|courses)\b',
        ).hasMatch(text) &&
        RegExp(
          r'\b(se hoc|chuong trinh|trong chuong trinh|program|study|hoc|cua toi|cua minh|my)\b',
        ).hasMatch(text);

    AskFptIntent intent;
    if (export && RegExp(r'\b(curriculum|chuong trinh)\b').hasMatch(text)) {
      intent = AskFptIntent.notesAddCurriculum;
    } else if (export && semester != null) {
      // Semester export is intentionally no longer a user-facing notes action.
      intent = AskFptIntent.semesterSubjects;
    } else if (export) {
      intent = AskFptIntent.notesAddSubject;
    } else if (semester == null &&
        personalPronoun &&
        asksAboutProgramSubjects &&
        !hasExplicitSubjectCode) {
      intent = AskFptIntent.personalCurriculumSubjects;
    } else if (RegExp(
      r'\b(tai lieu|material|textbook|sach)\b',
    ).hasMatch(text)) {
      intent = AskFptIntent.subjectMaterials;
    } else if (RegExp(
      r'\b(tien quyet|prerequisite|hoc truoc)\b',
    ).hasMatch(text)) {
      intent = AskFptIntent.subjectPrerequisite;
    } else if (RegExp(r'\b(tin chi|credit)\b').hasMatch(text)) {
      intent = AskFptIntent.subjectCredits;
    } else if (RegExp(
      r'\b(pe|thi|assessment|exam|kiem tra|danh gia)\b',
    ).hasMatch(text)) {
      intent = AskFptIntent.subjectAssessment;
    } else if (RegExp(
      r'\b(clo|outcome|hoc duoc gi|learning outcome)\b',
    ).hasMatch(text)) {
      intent = AskFptIntent.subjectOutcomes;
    } else if (RegExp(
      r'\b(specialization|chuyen nganh|combo)\b',
    ).hasMatch(text)) {
      intent = AskFptIntent.specializationOverview;
    } else if (RegExp(
      r'\b(ky sau|next semester|sau ky|sau hoc ky)\b',
    ).hasMatch(text)) {
      intent = AskFptIntent.futureSemester;
    } else if (semester != null ||
        RegExp(r'\b(con mon|phia truoc)\b').hasMatch(text)) {
      intent = AskFptIntent.semesterSubjects;
    } else if (RegExp(r'\b(curriculum|chuong trinh)\b').hasMatch(text)) {
      intent = AskFptIntent.curriculumOverview;
    } else if (_looksAcademic(text, question)) {
      intent = AskFptIntent.subjectOverview;
    } else {
      intent = AskFptIntent.outOfScope;
    }

    final personal =
        {
          AskFptIntent.semesterSubjects,
          AskFptIntent.personalCurriculumSubjects,
          AskFptIntent.futureSemester,
          AskFptIntent.specializationOverview,
          AskFptIntent.notesAddSemester,
          AskFptIntent.notesAddCurriculum,
        }.contains(intent) ||
        RegExp(r'\b(toi|minh|my|cua toi|cua minh)\b').hasMatch(text) &&
            !intent.name.startsWith('subject');

    return AskFptIntentResult(
      intent: intent,
      personal: personal,
      english: english,
      semester: semester,
      statedCurrentSemester: current,
    );
  }

  int? _semester(String text) {
    final match = RegExp(
      r'\b(?:hoc ky|ky|semester|sem)\s*(\d{1,2})\b',
    ).firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  bool _looksAcademic(String text, String original) {
    if (RegExp(r'\b[a-z]{2,6}\d{2,4}[a-z]?\b').hasMatch(text)) return true;
    if (RegExp(
      r'\b(mon|subject|course|hoc|syllabus|flm|fpt|pe|thi|exam|tin chi|credit|prerequisite|tai lieu|material)\b',
    ).hasMatch(text)) {
      return true;
    }
    return RegExp(r'\b[A-Z]{2,5}\b').hasMatch(original);
  }
}
