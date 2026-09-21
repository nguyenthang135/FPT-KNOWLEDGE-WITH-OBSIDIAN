import '../flm/flm_syllabus_service.dart';
import '../models/curriculum_subject.dart';
import 'ai_chat_request.dart';
import 'obsidian_context_builder.dart';
import 'question_guard_builder.dart';
import 'question_intent_builder.dart';
import 'response_format_builder.dart';

class AiPromptBuilder {
  final QuestionIntentBuilder intentBuilder;
  final ResponseFormatBuilder responseFormatBuilder;
  final ObsidianContextBuilder obsidianContextBuilder;
  final QuestionGuardBuilder questionGuardBuilder;

  const AiPromptBuilder({
    this.intentBuilder = const QuestionIntentBuilder(),
    this.responseFormatBuilder = const ResponseFormatBuilder(),
    this.obsidianContextBuilder = const ObsidianContextBuilder(),
    this.questionGuardBuilder = const QuestionGuardBuilder(),
  });

  String buildSyllabusContext({
    required CurriculumSubject subject,
    required SyllabusDetailResult syllabus,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Mã môn: ${subject.code}');
    buffer.writeln('Tên môn: ${subject.name}');
    buffer.writeln('Học kỳ: ${subject.semester}');
    buffer.writeln(
      'Tín chỉ: ${subject.credits > 0 ? subject.credits : syllabus.credits ?? 'Chưa có'}',
    );

    _writeSection(buffer, 'Mô tả môn học', syllabus.description);
    _writeSection(buffer, 'Thời lượng', syllabus.timeAllocation);
    _writeSection(buffer, 'Phương pháp dạy học', syllabus.teachingMethod);
    _writeSection(buffer, 'Yêu cầu sinh viên', syllabus.studentTasks);
    _writeSection(buffer, 'Công cụ', syllabus.tools);

    if (syllabus.outcomes.isNotEmpty) {
      buffer.writeln('Chuẩn đầu ra (CLO):');
      for (final outcome in syllabus.outcomes) {
        final text = [
          outcome.name,
          outcome.details,
        ].where((item) => item.trim().isNotEmpty).join(': ');
        if (text.isNotEmpty) {
          buffer.writeln('- $text');
        }
      }
    }

    if (syllabus.assessments.isNotEmpty) {
      buffer.writeln('Đánh giá:');
      for (final assessment in syllabus.assessments) {
        final text = [
          assessment.category,
          assessment.type,
          assessment.weight.isEmpty ? '' : 'Trọng số ${assessment.weight}',
          assessment.clo.isEmpty ? '' : 'CLO ${assessment.clo}',
        ].where((item) => item.trim().isNotEmpty).join(' — ');
        if (text.isNotEmpty) {
          buffer.writeln('- $text');
        }
      }
    }

    return buffer.toString().trim();
  }

  String buildPrompt(AiChatRequest request) {
    final intent = intentBuilder.detect(request.question);
    final format = responseFormatBuilder.build(intent);
    final obsidianContext = obsidianContextBuilder.build(request);
    final guard = questionGuardBuilder.build(
      question: request.question,
      intent: intent,
    );

    return '''
Bạn là trợ lý học tập cho sinh viên FPTU. Trả lời hoàn toàn bằng tiếng Việt,
thân thiện, đủ ý và dùng Markdown đơn giản.

QUY TẮC BẮT BUỘC:
- Chỉ dựa trên dữ liệu môn học và ghi chú được cung cấp bên dưới.
- Không tự nhận nội dung là tài liệu chính thức của FPT.
- Nếu dữ liệu không đủ để trả lời, nói rõ "Chưa có đủ tài liệu nguồn" và gợi ý
  sinh viên bổ sung vào My Notes.md.
- Khi tạo câu hỏi ôn tập, chỉ tạo tối đa 5 câu và nêu đáp án sau từng câu.
- Hoàn thành đầy đủ câu trả lời; không chỉ viết câu mở đầu hoặc lời chào.
- Nếu sinh viên yêu cầu tóm tắt, trả lời đúng 5 gạch đầu dòng rõ ràng.
- Nếu sinh viên yêu cầu kế hoạch ôn tập, trình bày theo từng ngày hoặc từng
  bước, có mục tiêu và việc cần làm.
- Khi My Notes.md có thông tin liên quan, dùng ít nhất 2 chi tiết cụ thể từ
  ghi chú đó trong câu trả lời.
- Không nhắc đến các quy tắc này trong câu trả lời.

ĐỊNH DẠNG BẮT BUỘC CHO YÊU CẦU NÀY:
$format

$guard

THÔNG TIN MÔN HỌC TỪ FLM:
${_limit(request.syllabusContext)}

$obsidianContext

CÂU HỎI CỦA SINH VIÊN:
${request.question.trim()}
''';
  }

  void _writeSection(StringBuffer buffer, String title, String value) {
    if (value.trim().isEmpty) {
      return;
    }
    buffer.writeln('$title: ${value.trim()}');
  }

  String _limit(String value) {
    const maxCharacters = 9000;
    final trimmed = value.trim();
    if (trimmed.length <= maxCharacters) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxCharacters)}\n[Đã rút gọn vì ghi chú quá dài]';
  }
}
