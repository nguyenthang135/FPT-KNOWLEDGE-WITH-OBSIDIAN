import 'study_intent.dart';

class ResponseFormatBuilder {
  const ResponseFormatBuilder();

  String build(StudyIntent intent) => switch (intent) {
    StudyIntent.summary =>
      'Trả lời đúng 5 gạch đầu dòng. Mỗi gạch đầu dòng có tiêu đề ngắn và một ý giải thích.',
    StudyIntent.assessment =>
      'Trình bày các hạng mục đánh giá bằng bảng Markdown: hạng mục, trọng số (nếu có) và điều cần chuẩn bị.',
    StudyIntent.studyPlan =>
      'Tạo kế hoạch theo ngày hoặc từng bước. Mỗi mục phải có: mục tiêu, nội dung ôn, một việc thực hành và tiêu chí hoàn thành.',
    StudyIntent.quiz =>
      'Tạo tối đa 5 câu quiz. Mỗi câu có đáp án ngay bên dưới và chỉ dựa trên dữ liệu nguồn.',
    StudyIntent.conceptExplanation =>
      'Giải thích theo 3 phần: định nghĩa, cách hoạt động hoặc đặc điểm, và một ví dụ từ dữ liệu nguồn. Nếu không có ví dụ, nói rõ.',
    StudyIntent.comparison =>
      'Dùng bảng Markdown để so sánh ít nhất 3 tiêu chí. Chỉ nêu điểm khác nhau được hỗ trợ bởi dữ liệu nguồn.',
    StudyIntent.noteReflection =>
      'Nêu 3 ưu tiên học tập rút ra từ My Notes.md, sau đó đề xuất các bước ôn tập phù hợp.',
    StudyIntent.outOfScope =>
      'Lịch sự nói rằng dữ liệu hiện có không chứa thông tin này. Gợi ý tối đa 2 câu hỏi phù hợp về syllabus hoặc My Notes.md.',
    StudyIntent.unclear =>
      'Hỏi lại một câu ngắn để làm rõ. Đưa tối đa 3 ví dụ về câu hỏi mà trợ lý có thể trả lời.',
    StudyIntent.general =>
      'Trả lời trực tiếp bằng 3 đến 5 gạch đầu dòng rõ ràng, ưu tiên dữ liệu liên quan nhất.',
  };
}
