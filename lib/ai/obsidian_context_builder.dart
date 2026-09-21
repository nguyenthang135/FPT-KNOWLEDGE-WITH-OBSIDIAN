import 'ai_chat_request.dart';

class ObsidianContextBuilder {
  const ObsidianContextBuilder();

  String build(AiChatRequest request) {
    if (!request.usesObsidianNotes) {
      return '''
TRẠNG THÁI GHI CHÚ OBSIDIAN:
My Notes.md chưa được dùng cho câu hỏi này. Không nói rằng bạn đã đọc ghi chú cá nhân.
''';
    }

    return '''
GHI CHÚ CÁ NHÂN TỪ OBSIDIAN (My Notes.md):
${_limit(request.obsidianNotes!)}

YÊU CẦU KHI DÙNG GHI CHÚ:
- Chỉ dùng ghi chú khi nội dung liên quan trực tiếp đến câu hỏi.
- Nếu ghi chú chỉ là khung trống hoặc không liên quan, nói rõ chưa có đủ ghi chú liên quan.
- Không bịa thêm nội dung vào ghi chú.
''';
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
