import 'package:yaml/yaml.dart';

import '../vault/note_metadata.dart';

class MarkdownParser {
  NoteMetadata parseMetadata(String content) {
    if (!content.startsWith('---')) {
      return NoteMetadata();
    }

    try {
      final endIndex = content.indexOf('---', 3);

      if (endIndex == -1) {
        return NoteMetadata();
      }

      final yamlText = content.substring(3, endIndex);

      final yaml = loadYaml(yamlText);

      if (yaml is! YamlMap) {
        return NoteMetadata();
      }

      final properties = <String, dynamic>{};

      yaml.forEach((key, value) {
        properties[key.toString()] = value;
      });

      final tags = <String>[];

      final yamlTags = yaml['tags'];

      if (yamlTags is YamlList) {
        for (final tag in yamlTags) {
          tags.add(tag.toString());
        }
      }

      return NoteMetadata(properties: properties, tags: tags);
    } catch (e) {
      // YAML lỗi → bỏ qua metadata
      // Markdown vẫn được render
      return NoteMetadata();
    }
  }
}
