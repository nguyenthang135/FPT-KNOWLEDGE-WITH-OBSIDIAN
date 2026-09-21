enum StudyIntent {
  summary,
  assessment,
  studyPlan,
  quiz,
  conceptExplanation,
  comparison,
  noteReflection,
  outOfScope,
  unclear,
  general,
}

extension StudyIntentLabel on StudyIntent {
  String get label => switch (this) {
    StudyIntent.summary => 'tóm tắt',
    StudyIntent.assessment => 'đánh giá môn học',
    StudyIntent.studyPlan => 'kế hoạch ôn tập',
    StudyIntent.quiz => 'câu hỏi ôn tập',
    StudyIntent.conceptExplanation => 'giải thích khái niệm',
    StudyIntent.comparison => 'so sánh kiến thức',
    StudyIntent.noteReflection => 'phân tích ghi chú cá nhân',
    StudyIntent.outOfScope => 'ngoài phạm vi tài liệu',
    StudyIntent.unclear => 'câu hỏi chưa rõ',
    StudyIntent.general => 'hỏi đáp môn học',
  };
}
