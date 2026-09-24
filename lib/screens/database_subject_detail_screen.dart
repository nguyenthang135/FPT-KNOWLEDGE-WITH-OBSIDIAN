import 'package:flutter/material.dart';

import '../database/database_repository.dart';
import '../notes/json_markdown_export_service.dart';

class DatabaseSubjectDetailScreen extends StatelessWidget {
  final String subjectCode;
  final Map<String, dynamic> subject;
  final DatabaseRepository repository;

  const DatabaseSubjectDetailScreen({
    super.key,
    required this.subjectCode,
    required this.subject,
    required this.repository,
  });

  Future<void> _export(BuildContext context) async {
    try {
      final result = await JsonMarkdownExportService(
        repository,
      ).addSubjectToMyNotes(subjectCode);
      if (!context.mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to My Notes: ${result.path}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add note: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final syllabusName = _text(subject['syllabusName']);
    final englishName = _text(subject['englishName']);
    final materials = _maps(subject['learningMaterials']);
    final outcomes = _maps(subject['learningOutcomes']);
    final assessments = _maps(subject['assessments']);

    return Scaffold(
      appBar: AppBar(
        title: Text(subjectCode),
        actions: [
          TextButton.icon(
            onPressed: () => _export(context),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Add to My Notes'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Text(subjectCode, style: Theme.of(context).textTheme.headlineLarge),
          if (syllabusName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(syllabusName, style: Theme.of(context).textTheme.titleLarge),
          ] else if (englishName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(englishName, style: Theme.of(context).textTheme.titleLarge),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (subject['credits'] != null)
                Chip(label: Text('${subject['credits']} credits')),
              if (subject['minimumPassMark'] != null)
                Chip(label: Text('Pass ≥ ${subject['minimumPassMark']}')),
            ],
          ),
          ..._infoSections(),
          if (materials.isNotEmpty) ...[
            const _Heading('Learning materials'),
            for (final item in materials)
              Card(
                child: ListTile(
                  leading: Icon(
                    item['isOnline'] == true
                        ? Icons.language
                        : Icons.menu_book_outlined,
                  ),
                  title: Text(_text(item['description'])),
                  subtitle: _joinedText([
                    _text(item['author']),
                    _text(item['publisher']),
                    _text(item['edition']),
                    _text(item['isbn']),
                    _text(item['note']),
                  ]),
                  trailing: item['isMain'] == true
                      ? const Chip(label: Text('Main'))
                      : null,
                ),
              ),
          ],
          if (outcomes.isNotEmpty) ...[
            const _Heading('Learning outcomes'),
            for (final item in outcomes)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(_text(item['name'])),
                  subtitle: Text(_text(item['details'])),
                ),
              ),
          ],
          if (assessments.isNotEmpty) ...[
            const _Heading('Assessments'),
            for (final item in assessments)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _text(item['category']),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            _text(item['weight']),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      for (final entry in <String, Object?>{
                        'Type': item['type'],
                        'Duration': item['duration'],
                        'Completion criteria': item['completionCriteria'],
                        'CLO': item['clo'],
                        'Question type': item['questionType'],
                        'Questions': item['numberOfQuestions'],
                        'Knowledge and skills': item['knowledgeAndSkill'],
                        'Grading guide': item['gradingGuide'],
                        'Note': item['note'],
                      }.entries)
                        if (_text(entry.value).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('${entry.key}: ${_text(entry.value)}'),
                        ],
                    ],
                  ),
                ),
              ),
          ],
          if (_text(subject['sourceUrl']).isNotEmpty) ...[
            const _Heading('Source'),
            SelectableText(_text(subject['sourceUrl'])),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<Widget> _infoSections() {
    final values = <String, Object?>{
      'Prerequisite': subject['prerequisite'],
      'Description': subject['description'],
      'Teaching method': subject['teachingMethod'],
      'Time allocation': subject['timeAllocation'],
      'Student tasks': subject['studentTasks'],
      'Tools': subject['tools'],
    };
    return [
      for (final entry in values.entries)
        if (_text(entry.value).isNotEmpty) ...[
          _Heading(entry.key),
          SelectableText(_text(entry.value)),
        ],
    ];
  }

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : const [];

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static Widget? _joinedText(List<String> values) {
    final text = values.where((value) => value.isNotEmpty).join('\n');
    return text.isEmpty ? null : Text(text);
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

Future<void> openDatabaseSubject(
  BuildContext context,
  DatabaseRepository repository,
  String code,
) async {
  final subject = await repository.loadSubject(code);
  if (!context.mounted) return;
  if (subject == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('No syllabus data for $code.')));
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DatabaseSubjectDetailScreen(
        subjectCode: code,
        subject: subject,
        repository: repository,
      ),
    ),
  );
}
