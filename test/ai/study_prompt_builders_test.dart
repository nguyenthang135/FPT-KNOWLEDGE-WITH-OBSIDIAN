import 'package:flutter_test/flutter_test.dart';

import 'package:fptu_se_brain/ai/ai_chat_request.dart';
import 'package:fptu_se_brain/ai/ai_prompt_builder.dart';
import 'package:fptu_se_brain/ai/question_intent_builder.dart';
import 'package:fptu_se_brain/ai/study_intent.dart';

void main() {
  const intentBuilder = QuestionIntentBuilder();

  group('QuestionIntentBuilder', () {
    test('recognises common study questions', () {
      expect(
        intentBuilder.detect('Tóm tắt môn này thành 5 ý'),
        StudyIntent.summary,
      );
      expect(
        intentBuilder.detect('Lập kế hoạch ôn tập 5 ngày'),
        StudyIntent.studyPlan,
      );
      expect(
        intentBuilder.detect('Cache khác RAM như thế nào?'),
        StudyIntent.comparison,
      );
      expect(
        intentBuilder.detect('Tạo quiz 3 câu'),
        StudyIntent.quiz,
      );
    });

    test('recognises unclear and out-of-scope questions', () {
      expect(intentBuilder.detect('alo'), StudyIntent.unclear);
      expect(
        intentBuilder.detect('Học phí môn này là bao nhiêu?'),
        StudyIntent.outOfScope,
      );
    });
  });

  test('prompt requires a complete note-based study plan', () {
    const request = AiChatRequest(
      curriculumCode: 'BIT_SE_K18D_19A',
      subjectCode: 'CEA201',
      subjectName: 'Computer Organization',
      syllabusContext: 'Có nội dung CPU và bộ nhớ.',
      question: 'Lập kế hoạch ôn tập 5 ngày từ ghi chú của tôi.',
      obsidianNotes: 'Em còn yếu CPU, cache và thanh ghi.',
    );

    const promptBuilder = AiPromptBuilder();
    final prompt = promptBuilder.buildPrompt(request);

    expect(prompt, contains('Loại yêu cầu đã nhận diện: kế hoạch ôn tập'));
    expect(prompt, contains('Mỗi mục phải có: mục tiêu'));
    expect(prompt, contains('CPU, cache và thanh ghi'));
    expect(prompt, contains('ít nhất 2 chi tiết cụ thể'));
  });
}
