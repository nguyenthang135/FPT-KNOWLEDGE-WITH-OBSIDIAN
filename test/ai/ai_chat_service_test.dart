import 'package:flutter_test/flutter_test.dart';

import 'package:fptu_se_brain/ai/ai_chat_request.dart';
import 'package:fptu_se_brain/ai/mock_ai_chat_service.dart';

void main() {
  const service = MockAiChatService();

  test('Mock AI identifies Obsidian notes as a source', () async {
    const request = AiChatRequest(
      curriculumCode: 'BIT_SE_K18D_19A',
      subjectCode: 'PRM393',
      subjectName: 'Mobile Programming',
      syllabusContext: 'Môn học về lập trình di động.',
      question: 'Tạo quiz 3 câu',
      obsidianNotes: 'StatefulWidget dùng khi giao diện thay đổi.',
    );

    final response = await service.ask(request);

    expect(response.isDemo, isTrue);
    expect(response.sourceLabel, contains('My Notes.md'));
    expect(response.answer, contains('PRM393'));
  });
}
