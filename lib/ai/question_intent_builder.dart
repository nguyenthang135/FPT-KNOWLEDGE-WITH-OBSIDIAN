import 'study_intent.dart';

class QuestionIntentBuilder {
  const QuestionIntentBuilder();

  StudyIntent detect(String question) {
    final text = question.trim().toLowerCase();

    if (text.length < 4 || _isOnlyFiller(text)) {
      return StudyIntent.unclear;
    }
    if (_containsAny(text, const [
      'học phí',
      'hoc phi',
      'giảng viên',
      'giang vien',
      'thời khóa biểu',
      'thoi khoa bieu',
      'điểm của tôi',
      'diem cua toi',
      'đăng ký môn',
      'dang ky mon',
    ])) {
      return StudyIntent.outOfScope;
    }
    if (_containsAny(text, const [
      'tóm tắt',
      'tom tat',
      'nội dung chính',
      'noi dung chinh',
    ])) {
      return StudyIntent.summary;
    }
    if (_containsAny(text, const [
      'đánh giá',
      'danh gia',
      'trọng số',
      'trong so',
      'chấm điểm',
      'cham diem',
    ])) {
      return StudyIntent.assessment;
    }
    if (_containsAny(text, const [
      'kế hoạch',
      'ke hoach',
      'lộ trình',
      'lo trinh',
      'ôn tập',
      'on tap',
      'lịch học',
      'lich hoc',
    ])) {
      return StudyIntent.studyPlan;
    }
    if (_containsAny(text, const [
      'quiz',
      'trắc nghiệm',
      'trac nghiem',
      'câu hỏi ôn',
      'cau hoi on',
    ])) {
      return StudyIntent.quiz;
    }
    if (_containsAny(text, const [
      'so sánh',
      'so sanh',
      'phân biệt',
      'phan biet',
      'khác nhau',
      'khac nhau',
      'khác',
      'khac',
    ])) {
      return StudyIntent.comparison;
    }
    if (_containsAny(text, const [
      'ghi chú',
      'ghi chu',
      'my notes',
      'tôi yếu',
      'toi yeu',
      'điểm yếu',
      'diem yeu',
    ])) {
      return StudyIntent.noteReflection;
    }
    if (_containsAny(text, const [
      'giải thích',
      'giai thich',
      'là gì',
      'la gi',
      'hoạt động',
      'hoat dong',
    ])) {
      return StudyIntent.conceptExplanation;
    }
    return StudyIntent.general;
  }

  bool _containsAny(String text, List<String> terms) =>
      terms.any(text.contains);

  bool _isOnlyFiller(String text) => const {
    'giúp tôi',
    'giup toi',
    'help',
    'alo',
    'xin chào',
  }.contains(text);
}
