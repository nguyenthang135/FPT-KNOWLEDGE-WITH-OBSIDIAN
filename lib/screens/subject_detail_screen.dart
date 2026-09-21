import 'package:flutter/material.dart';

import '../ai/widgets/ai_assistant_dialog.dart';
import '../ai/widgets/ai_floating_button.dart';
import '../design_system/fpt_loading.dart';
import '../flm/flm_syllabus_service.dart';
import '../models/curriculum_subject.dart';

class SubjectDetailScreen extends StatefulWidget {
  final String curriculumCode;
  final CurriculumSubject subject;

  const SubjectDetailScreen({
    super.key,
    required this.curriculumCode,
    required this.subject,
  });

  @override
  State<SubjectDetailScreen> createState() =>
      _SubjectDetailScreenState();
}

class _SubjectDetailScreenState
    extends State<SubjectDetailScreen> {
  final FlmSyllabusService _service =
      FlmSyllabusService();

  bool _loading = true;
  String? _error;

  SyllabusDetailResult? _syllabus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final startTime = DateTime.now();
    try {
      final syllabus = await _service.loadExactSyllabus(
        widget.subject.code,
      );

      final elapsed = DateTime.now().difference(startTime);
      const minDuration = Duration(milliseconds: 3800);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }

      if (!mounted) return;

      setState(() {
        _syllabus = syllabus;
        _loading = false;
      });
    } catch (error) {
      final elapsed = DateTime.now().difference(startTime);
      const minDuration = Duration(milliseconds: 3000);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }

      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.subject.code),
        ),
        body: FptTechLoading(
          title: widget.subject.code,
          subtitle: 'Loading subject syllabus & knowledge graph from FLM...',
        ),
      );
    }

    if (_error != null ||
        _syllabus == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.subject.code,
          ),
        ),
        body: Center(
          child: Padding(
            padding:
                const EdgeInsets.all(
              32,
            ),
            child: Text(
              'Could not load syllabus.\n\n'
              '${_error ?? ''}',
              textAlign:
                  TextAlign.center,
            ),
          ),
        ),
      );
    }

    final syllabus =
        _syllabus!;

    final names =
        widget.subject.name.split('_');

    final englishName =
        names.isNotEmpty
            ? names.first.trim()
            : widget.subject.name;

    final vietnameseName =
        names.length > 1
            ? names
                .sublist(1)
                .join('_')
                .trim()
            : '';

    final credits =
        widget.subject.credits > 0
            ? widget.subject.credits
            : syllabus.credits;

    final prerequisite =
        widget.subject.hasPrerequisite
            ? widget.subject.prerequisite
            : syllabus.prerequisite;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.subject.code),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(32),
        children: [
          Text(
            widget.subject.code,
            style: Theme.of(context)
                .textTheme
                .headlineLarge,
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            englishName,
            style: Theme.of(context)
                .textTheme
                .headlineSmall,
          ),

          if (vietnameseName
              .isNotEmpty) ...[
            const SizedBox(
              height: 4,
            ),

            Text(vietnameseName),
          ],

          const SizedBox(
            height: 20,
          ),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Chip(
                label: Text(
                  'Semester '
                  '${widget.subject.semester}',
                ),
              ),

              if (credits != null)
                Chip(
                  label: Text(
                    '$credits credits',
                  ),
                ),

              if (syllabus
                      .minimumPassMark !=
                  null)
                Chip(
                  label: Text(
                    'Pass ≥ '
                    '${syllabus.minimumPassMark}',
                  ),
                ),
            ],
          ),

          if (syllabus
              .description
              .isNotEmpty) ...[
            const SizedBox(
              height: 32,
            ),

            _SectionTitle(
              title:
                  'About this subject',
            ),

            Text(
              syllabus.description,
            ),
          ],

          if (syllabus
              .timeAllocation
              .isNotEmpty) ...[
            const SizedBox(
              height: 24,
            ),

            _InfoRow(
              label: 'Study time',
              value:
                  syllabus.timeAllocation,
            ),
          ],

          if (syllabus
              .teachingMethod
              .isNotEmpty)
            _InfoRow(
              label:
                  'Teaching method',
              value:
                  syllabus.teachingMethod,
            ),

          if (prerequisite
              .trim()
              .isNotEmpty)
            _InfoRow(
              label: 'Prerequisite',
              value: prerequisite,
            ),

          const SizedBox(
            height: 36,
          ),

          _SectionTitle(
            title:
                'How you are graded',
          ),

          if (syllabus
              .assessments
              .isEmpty)
            const Text(
              'No assessment information found.',
            )
          else
            for (final assessment
                in syllabus.assessments)
              _AssessmentCard(
                assessment:
                    assessment,
              ),

          const SizedBox(
            height: 36,
          ),

          _SectionTitle(
            title:
                'Practical work & assignments',
          ),

          ..._buildPracticalWork(
            syllabus.assessments,
          ),

          const SizedBox(
            height: 36,
          ),

          _SectionTitle(
            title: 'What you need',
          ),

          if (syllabus
              .tools
              .isNotEmpty)
            _RequirementBlock(
              icon:
                  Icons.build_outlined,
              title: 'Tools',
              text: syllabus.tools,
            ),

          if (syllabus
              .studentTasks
              .isNotEmpty)
            _RequirementBlock(
              icon: Icons.task_alt,
              title:
                  'Student requirements',
              text:
                  syllabus.studentTasks,
            ),

          const SizedBox(
            height: 36,
          ),

          _SectionTitle(
            title:
                'Materials to learn',
          ),

          if (syllabus
              .materials
              .isEmpty)
            const Text(
              'No learning materials found.',
            )
          else
            for (final material
                in syllabus.materials)
              _MaterialCard(
                material: material,
              ),

          const SizedBox(
            height: 36,
          ),

          _SectionTitle(
            title:
                'What you will learn',
          ),

          if (syllabus
              .outcomes
              .isEmpty)
            const Text(
              'No learning outcomes found.',
            )
          else
            for (final outcome
                in syllabus.outcomes)
              _OutcomeTile(
                outcome: outcome,
              ),

          const SizedBox(
            height: 40,
          ),
        ],
      ),
      floatingActionButton: AiFloatingButton(
        tooltip: 'Hỏi Trợ lý AI (${widget.subject.code})',
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (_) => AiAssistantDialog(
              curriculumCode: widget.curriculumCode,
              subject: widget.subject,
              syllabus: syllabus,
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildPracticalWork(
    List<SyllabusAssessment>
        assessments,
  ) {
    final practical =
        assessments.where(
      (assessment) {
        final category =
            assessment.category
                .toLowerCase();

        return category.contains(
              'assignment',
            ) ||
            category.contains(
              'practical',
            ) ||
            category.contains(
              'workshop',
            ) ||
            category.contains(
              'project',
            );
      },
    ).toList();

    if (practical.isEmpty) {
      return [
        const Text(
          'No specific project or practical-work requirement was found in the syllabus.',
        ),
      ];
    }

    return practical
        .map(
          (assessment) =>
              _PracticalCard(
            assessment:
                assessment,
          ),
        )
        .toList();
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(
              fontWeight:
                  FontWeight.bold,
            ),
      ),
    );
  }
}

class _AssessmentCard
    extends StatelessWidget {
  final SyllabusAssessment assessment;

  const _AssessmentCard({
    required this.assessment,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    assessment.category,
                    style:
                        const TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                Text(
                  assessment.weight,
                  style:
                      const TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),

            if (assessment
                .duration
                .isNotEmpty) ...[
              const SizedBox(
                height: 8,
              ),
              Text(
                'Duration: '
                '${assessment.duration}',
              ),
            ],

            if (assessment
                .numberOfQuestions
                .isNotEmpty)
              Text(
                'Questions: '
                '${assessment.numberOfQuestions}',
              ),

            if (assessment
                .questionType
                .isNotEmpty) ...[
              const SizedBox(
                height: 8,
              ),
              Text(
                assessment.questionType,
              ),
            ],

            if (assessment
                .knowledgeAndSkill
                .isNotEmpty) ...[
              const SizedBox(
                height: 10,
              ),
              Text(
                assessment
                    .knowledgeAndSkill,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PracticalCard
    extends StatelessWidget {
  final SyllabusAssessment assessment;

  const _PracticalCard({
    required this.assessment,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: ListTile(
        title: Text(
          assessment.category,
        ),
        subtitle: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (assessment
                .knowledgeAndSkill
                .isNotEmpty)
              Text(
                assessment
                    .knowledgeAndSkill,
              ),

            if (assessment
                .gradingGuide
                .isNotEmpty) ...[
              const SizedBox(
                height: 6,
              ),
              Text(
                assessment.gradingGuide,
              ),
            ],
          ],
        ),
        trailing:
            Text(assessment.weight),
      ),
    );
  }
}

class _RequirementBlock
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _RequirementBlock({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(icon),

            const SizedBox(
              width: 14,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 6,
                  ),

                  Text(text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialCard
    extends StatelessWidget {
  final SyllabusMaterial material;

  const _MaterialCard({
    required this.material,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: ListTile(
        leading: Icon(
          material.isOnline
              ? Icons.language
              : Icons.menu_book_outlined,
        ),

        title:
            Text(material.description),

        subtitle: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (material
                .author
                .isNotEmpty)
              Text(material.author),

            if (material
                .edition
                .isNotEmpty)
              Text(material.edition),

            if (material
                .note
                .isNotEmpty)
              SelectableText(
                material.note,
              ),
          ],
        ),

        trailing: material.isMain
            ? const Chip(
                label:
                    Text('Main'),
              )
            : null,
      ),
    );
  }
}

class _OutcomeTile
    extends StatelessWidget {
  final SyllabusLearningOutcome outcome;

  const _OutcomeTile({
    required this.outcome,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 8,
      ),
      child: ListTile(
        leading:
            const Icon(
          Icons.check_circle_outline,
        ),
        title:
            Text(outcome.name),
        subtitle:
            Text(outcome.details),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),

          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}