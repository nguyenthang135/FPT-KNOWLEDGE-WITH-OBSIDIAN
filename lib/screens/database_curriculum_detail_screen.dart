import 'package:flutter/material.dart';

import '../ai/ask_fpt_models.dart';
import '../database/database_repository.dart';
import '../flm/flm_combo_service.dart';
import '../notes/json_markdown_export_service.dart';
import '../settings/app_settings.dart';
import 'database_subject_detail_screen.dart';

class DatabaseCurriculumDetailScreen extends StatefulWidget {
  final DatabaseRepository repository;
  final String curriculumCode;
  final bool showUseAction;
  final VoidCallback? onSelectionChanged;

  const DatabaseCurriculumDetailScreen({
    super.key,
    required this.repository,
    required this.curriculumCode,
    this.showUseAction = true,
    this.onSelectionChanged,
  });

  @override
  State<DatabaseCurriculumDetailScreen> createState() =>
      _DatabaseCurriculumDetailScreenState();
}

class _DatabaseCurriculumDetailScreenState
    extends State<DatabaseCurriculumDetailScreen> {
  DatabaseCurriculum? _curriculum;
  List<SpecializationCombo> _specializations = const [];
  SpecializationCombo? _selectedSpecialization;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object?>([
        widget.repository.loadCurriculum(widget.curriculumCode),
        widget.repository.loadProfessionalSpecializations(
          widget.curriculumCode,
        ),
        AppSettings.instance.getSpecialization(widget.curriculumCode),
      ]);
      if (!mounted) return;
      final choices = values[1] as List<SpecializationCombo>;
      final saved = values[2] as SpecializationCombo?;
      setState(() {
        _curriculum = values[0] as DatabaseCurriculum?;
        _specializations = choices;
        _selectedSpecialization = saved == null
            ? null
            : choices.cast<SpecializationCombo?>().firstWhere(
                (item) => item?.name == saved.name,
                orElse: () => saved,
              );
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _useCurriculum() async {
    await AppSettings.instance.setCurrentCurriculum(widget.curriculumCode);
    await AppSettings.instance.setActiveContextProvenance(
      ActiveContextProvenance.explicitUseSelection,
    );
    widget.onSelectionChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved as My Curriculum.')));
  }

  Future<void> _selectSpecialization(SpecializationCombo value) async {
    await AppSettings.instance.setSpecialization(widget.curriculumCode, value);
    if (!mounted) return;
    setState(() => _selectedSpecialization = value);
  }

  Future<void> _runExport(
    Future<MarkdownExportResult?> Function() operation,
  ) async {
    try {
      final result = await operation();
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to My Notes: ${result.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add note: $error')));
    }
  }

  Future<void> _exportCurriculum() => _runExport(
    () => JsonMarkdownExportService(
      widget.repository,
    ).addCurriculumToMyNotes(widget.curriculumCode),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.curriculumCode),
        actions: [
          TextButton.icon(
            onPressed: _exportCurriculum,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Add to My Notes'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load curriculum.\n$_error'),
        ),
      );
    }
    final curriculum = _curriculum;
    if (curriculum == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final bySemester = <int, List<DatabaseCurriculumSubject>>{};
    for (final subject in curriculum.subjects) {
      bySemester.putIfAbsent(subject.semester, () => []).add(subject);
    }
    final semesters = <int>{
      ...bySemester.keys,
      ...?_selectedSpecialization?.subjects.map((item) => item.semester),
    }.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(curriculum.code, style: Theme.of(context).textTheme.headlineLarge),
        if (curriculum.name.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(curriculum.name, style: Theme.of(context).textTheme.titleLarge),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('${curriculum.subjects.length} curriculum slots')),
            if (curriculum.totalCredits != null)
              Chip(label: Text('${curriculum.totalCredits} total credits')),
            if (_specializations.isNotEmpty)
              Chip(label: Text('${_specializations.length} specializations')),
          ],
        ),
        if (widget.showUseAction) ...[
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _useCurriculum,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Use this curriculum'),
            ),
          ),
        ],
        if (_specializations.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Specialization', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedSpecialization?.name,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Choose locally',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final choice in _specializations)
                DropdownMenuItem(
                  value: choice.name,
                  child: Text(choice.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (name) {
              if (name == null) return;
              _selectSpecialization(
                _specializations.firstWhere((item) => item.name == name),
              );
            },
          ),
          if (_selectedSpecialization case final selected?) ...[
            if (selected.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(selected.note),
            ],
            const SizedBox(height: 8),
            Text('${selected.subjects.length} specialization subjects'),
          ],
        ],
        const SizedBox(height: 28),
        for (final semester in semesters)
          _SemesterCard(
            semester: semester,
            subjects: bySemester[semester] ?? const [],
            specialization: _selectedSpecialization,
            repository: widget.repository,
          ),
      ],
    );
  }
}

class _SemesterCard extends StatelessWidget {
  final int semester;
  final List<DatabaseCurriculumSubject> subjects;
  final SpecializationCombo? specialization;
  final DatabaseRepository repository;

  const _SemesterCard({
    required this.semester,
    required this.subjects,
    required this.specialization,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final comboSubjects =
        specialization?.subjects
            .where((item) => item.semester == semester)
            .toList() ??
        const <ComboSubject>[];
    final normalSubjects = subjects
        .where((item) => !item.isComboPlaceholder)
        .toList();
    final placeholders = subjects
        .where((item) => item.isComboPlaceholder)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        initiallyExpanded: semester <= 1,
        title: Text(semester == 0 ? 'Preparation' : 'Semester $semester'),
        subtitle: Text(
          '${normalSubjects.length + comboSubjects.length} subjects',
        ),
        children: [
          for (final subject in normalSubjects)
            _SubjectTile(
              code: subject.code,
              name: subject.name,
              credits: subject.credits,
              prerequisite: subject.prerequisite,
              repository: repository,
            ),
          for (final subject in comboSubjects)
            _SubjectTile(
              code: subject.code,
              name: subject.name,
              credits: 0,
              prerequisite: '',
              repository: repository,
              specialization: true,
            ),
          if (comboSubjects.isEmpty)
            for (final placeholder in placeholders)
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: Text(placeholder.code),
                subtitle: const Text(
                  'Choose a specialization to fill this slot',
                ),
              ),
        ],
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  final String code;
  final String name;
  final int credits;
  final String prerequisite;
  final DatabaseRepository repository;
  final bool specialization;

  const _SubjectTile({
    required this.code,
    required this.name,
    required this.credits,
    required this.prerequisite,
    required this.repository,
    this.specialization = false,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      specialization ? Icons.star_outline : Icons.menu_book_outlined,
    ),
    title: Text(code),
    subtitle: Text(
      [
        name,
        if (prerequisite.trim().isNotEmpty)
          'Prerequisite: ${prerequisite.trim()}',
      ].join('\n'),
    ),
    trailing: credits > 0 ? Text('$credits cr') : null,
    onTap: () => openDatabaseSubject(context, repository, code),
  );
}
