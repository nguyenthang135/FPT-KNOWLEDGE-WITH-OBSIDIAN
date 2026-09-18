import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_se_brain/vault/markdown_parser.dart';

void main() {
  late MarkdownParser parser;

  setUp(() {
    parser = MarkdownParser();
  });

  group('MarkdownParser - Test YAML Lỗi', () {
    test('Nội dung không có frontmatter (không bắt đầu bằng ---)', () {
      const content = 'Đây là nội dung ghi chú thông thường không có YAML header.';
      final metadata = parser.parseMetadata(content);

      expect(metadata.properties, isEmpty);
      expect(metadata.tags, isEmpty);
    });

    test('YAML frontmatter thiếu dấu đóng ---', () {
      const content = '''---
title: Test Note
tags: [test, markdown]
Đây là nội dung note nhưng quên đóng --- ở cuối YAML.
''';
      final metadata = parser.parseMetadata(content);

      expect(metadata.properties, isEmpty);
      expect(metadata.tags, isEmpty);
    });

    test('YAML sai cú pháp (Cú pháp YAML không hợp lệ làm YamlParser ném ngoại lệ)', () {
      const content = '''---
title: Note Lỗi YAML
tags: [tag1, tag2
key_loi: : : : giá trị không hợp lệ
---
# Tiêu đề ghi chú
Nội dung ghi chú vẫn được giữ lại dù YAML bị lỗi.
''';
      final metadata = parser.parseMetadata(content);

      // Cú pháp lỗi sẽ bị bắt bởi catch block trong parseMetadata
      // Trả về NoteMetadata rỗng
      expect(metadata.properties, isEmpty);
      expect(metadata.tags, isEmpty);
    });

    test('YAML hợp lệ nhưng không phải là YamlMap (ví dụ: là YamlList hoặc chuỗi đơn)', () {
      const content = '''---
- item1
- item2
---
# Nội dung note
''';
      final metadata = parser.parseMetadata(content);

      expect(metadata.properties, isEmpty);
      expect(metadata.tags, isEmpty);
    });

    test('YAML hợp lệ cấu trúc Map', () {
      const content = '''---
title: Note Hợp Lệ
tags:
  - flutter
  - dart
author: Admin
---
# Nội dung ghi chú
''';
      final metadata = parser.parseMetadata(content);

      expect(metadata.properties['title'], 'Note Hợp Lệ');
      expect(metadata.properties['author'], 'Admin');
      expect(metadata.tags, equals(['flutter', 'dart']));
    });
  });
}
