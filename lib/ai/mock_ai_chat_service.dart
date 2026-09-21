import 'ai_chat_request.dart';
import 'ai_chat_response.dart';
import 'ai_chat_service.dart';

class MockAiChatService implements AiChatService {
  const MockAiChatService();

  @override
  Future<AiChatResponse> ask(AiChatRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));

    final question = request.question.toLowerCase();
    final noteHint = request.usesObsidianNotes
        ? '\n\nMình cũng đã dùng nội dung trong `My Notes.md` của bạn làm ngữ cảnh.'
        : '';

    final answer = question.contains('quiz') || question.contains('câu hỏi')
        ? _quizAnswer(request)
        : question.contains('đánh giá') || question.contains('điểm')
        ? _assessmentAnswer(request, noteHint)
        : _generalAnswer(request, noteHint);

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

  String _generalAnswer(AiChatRequest request, String noteHint) =>
      '''
Với môn **${request.subjectCode} — ${request.subjectName}**, bạn nên bắt đầu từ mô tả môn học, CLO và các yêu cầu đánh giá trong syllabus.$noteHint

Câu hỏi của bạn: **${request.question.trim()}**

*Đây là dữ liệu Mock AI để kiểm tra giao diện. Khi có Gemini API key, app sẽ trả lời theo nội dung môn học thật.*''';
}
