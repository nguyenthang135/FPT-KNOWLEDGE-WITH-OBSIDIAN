import 'ai_chat_request.dart';
import 'ai_chat_response.dart';
import 'ai_chat_service.dart';
import 'question_intent_builder.dart';
import 'study_intent.dart';

class MockAiChatService implements AiChatService {
  final QuestionIntentBuilder _intentBuilder;

  const MockAiChatService({
    QuestionIntentBuilder intentBuilder = const QuestionIntentBuilder(),
  }) : _intentBuilder = intentBuilder;

  @override
  Future<AiChatResponse> ask(AiChatRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));

    final noteHint = request.usesObsidianNotes
        ? '\n\nMình cũng đã dùng nội dung trong `My Notes.md` của bạn làm ngữ cảnh.'
        : '';
    final intent = _intentBuilder.detect(request.question);
    final answer = switch (intent) {
      StudyIntent.quiz => _quizAnswer(request),
      StudyIntent.assessment => _assessmentAnswer(request, noteHint),
      StudyIntent.summary => _summaryAnswer(request, noteHint),
      StudyIntent.studyPlan => _planAnswer(request, noteHint),
      StudyIntent.comparison => _comparisonAnswer(request, noteHint),
      StudyIntent.outOfScope => _outOfScopeAnswer(),
      StudyIntent.unclear => _clarificationAnswer(),
      _ => _generalAnswer(request, noteHint),
    };

    return AiChatResponse(
      answer: answer,
      sourceLabel: request.sourceLabel,
      isDemo: true,
    );
  }

  String _quizAnswer(AiChatRequest request) =>
      '''
Đây là bộ câu hỏi ôn tập mẫu cho **${request.subjectCode}**:

1. Mục tiêu học tập quan trọng của môn là gì?
   - Hãy trả lời dựa trên các CLO và ghi chú đã cung cấp.

2. Hình thức đánh giá nào cần được ưu tiên chuẩn bị?
   - Xem mục Assessment của môn để xác định trọng số và yêu cầu.

3. Kiến thức nào trong ghi chú của bạn cần ôn lại trước?
   - Chọn một ý trong `My Notes.md` và giải thích bằng lời của bạn.

*Đây là dữ liệu Mock AI để kiểm tra giao diện; hãy cấu hình Gemini để có câu trả lời AI thật.*''';

  String _assessmentAnswer(AiChatRequest request, String noteHint) =>
      '''
Môn **${request.subjectCode}** có thông tin đánh giá trong syllabus FLM.
Bạn nên xem phần **How you are graded** để biết từng hạng mục, trọng số và CLO liên quan.$noteHint

*Đây là dữ liệu Mock AI để kiểm tra giao diện.*''';

  String _summaryAnswer(AiChatRequest request, String noteHint) =>
      '''
Đây là phần tóm tắt mẫu cho **${request.subjectCode}**:

1. Mục tiêu: xem mô tả môn và các CLO trong syllabus.
2. Nội dung: ôn những chủ đề được nêu trong dữ liệu FLM.
3. Yêu cầu: theo dõi nhiệm vụ sinh viên và công cụ cần dùng.
4. Đánh giá: ưu tiên hạng mục có trọng số cao.
5. Ôn tập: dùng câu hỏi trong ghi chú để tự kiểm tra.$noteHint

*Đây là dữ liệu Mock AI để kiểm tra giao diện.*''';

  String _planAnswer(AiChatRequest request, String noteHint) =>
      '''
Kế hoạch ôn tập mẫu cho **${request.subjectCode}**:

- Ngày 1: đọc mô tả môn và chọn 2 mục tiêu học tập.
- Ngày 2: ôn một chủ đề trong syllabus, sau đó ghi 3 ý vào note.
- Ngày 3: làm câu hỏi tự kiểm tra và ghi lại phần còn yếu.
- Ngày 4: xem lại phần đánh giá, ưu tiên hạng mục quan trọng.
- Ngày 5: tổng hợp note và tự tạo quiz ngắn.$noteHint

*Đây là dữ liệu Mock AI để kiểm tra giao diện.*''';

  String _comparisonAnswer(AiChatRequest request, String noteHint) =>
      '''
Mock AI cần dữ liệu so sánh cụ thể trong syllabus hoặc My Notes.md của **${request.subjectCode}**.
Bạn có thể hỏi lại theo mẫu: “A khác B như thế nào?”$noteHint

*Đây là dữ liệu Mock AI để kiểm tra giao diện.*''';

  String _outOfScopeAnswer() =>
      '''
Chưa có đủ tài liệu nguồn để trả lời thông tin này. Trợ lý hiện chỉ dùng syllabus FLM và My Notes.md.

Bạn có thể hỏi về nội dung môn, cách đánh giá hoặc kế hoạch ôn tập.

*Đây là dữ liệu Mock AI để kiểm tra giao diện.*''';

  String _clarificationAnswer() =>
      '''
Bạn hãy hỏi rõ hơn một chút nhé. Ví dụ:

- “Tóm tắt môn này thành 5 ý.”
- “Môn được đánh giá như thế nào?”
- “Tạo 3 câu quiz dựa trên My Notes.md.”

*Đây là dữ liệu Mock AI để kiểm tra giao diện.*''';

  String _generalAnswer(AiChatRequest request, String noteHint) =>
      '''
Với môn **${request.subjectCode} — ${request.subjectName}**, bạn nên bắt đầu từ mô tả môn học, CLO và các yêu cầu đánh giá trong syllabus.$noteHint

Câu hỏi của bạn: **${request.question.trim()}**

*Đây là dữ liệu Mock AI để kiểm tra giao diện. Khi có Gemini API key, app sẽ trả lời theo nội dung môn học thật.*''';
}
