class AiChatRequest {
  final String curriculumCode;
  final String subjectCode;
  final String subjectName;
  final String syllabusContext;
  final String question;
  final String? obsidianNotes;

  const AiChatRequest({
    required this.curriculumCode,
    required this.subjectCode,
    required this.subjectName,
    required this.syllabusContext,
    required this.question,
    this.obsidianNotes,
  });

  bool get usesObsidianNotes =>
      obsidianNotes != null && obsidianNotes!.trim().isNotEmpty;

  String get sourceLabel => usesObsidianNotes
      ? 'Syllabus FLM + My Notes.md từ Obsidian'
      : 'Syllabus FLM';
}
