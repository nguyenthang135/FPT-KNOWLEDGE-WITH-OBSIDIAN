import 'package:flutter/material.dart';

import '../flm/flm_combo_service.dart';
import '../flm/flm_session.dart';
import '../models/curriculum_subject.dart';
import '../obsidian/obsidian_service.dart';
import '../settings/app_settings.dart';
import 'combo_selection_screen.dart';
import 'flm_login_screen.dart';
import 'subject_detail_screen.dart';

class CurriculumOverviewScreen extends StatefulWidget {
  final String curriculumCode;

  const CurriculumOverviewScreen({
    super.key,
    required this.curriculumCode,
  });

  @override
  State<CurriculumOverviewScreen> createState() =>
      _CurriculumOverviewScreenState();
}

class _CurriculumOverviewScreenState
    extends State<CurriculumOverviewScreen> {
  bool _loading = true;
  bool _loggingOut = false;
  bool _exportingObsidian = false;

  String? _error;

  List<CurriculumSubject> _subjects = [];

  SpecializationCombo? _selectedCombo;

  final ObsidianService _obsidianService =
      ObsidianService();

  String? _connectedVaultPath;

  int _exportCurrent = 0;
  int _exportTotal = 0;
  String _exportMessage = '';

  @override
  void initState() {
    super.initState();

    _restoreVault();
    _loadSubjects();
  }

  Future<void> _restoreVault() async {
    final path =
        await _obsidianService.getSavedVaultPath();

    if (!mounted) {
      return;
    }

    setState(() {
      _connectedVaultPath = path;
    });
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects =
          await FlmSession.instance.getCurriculumSubjects();

      if (!mounted) {
        return;
      }

      setState(() {
        _subjects = subjects;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _chooseSpecialization() async {
    final combo =
        await Navigator.of(context).push<SpecializationCombo>(
      MaterialPageRoute(
        builder: (_) => ComboSelectionScreen(
          curriculumCode: widget.curriculumCode,
        ),
      ),
    );

    if (combo == null || !mounted) {
      return;
    }

    setState(() {
      _selectedCombo = combo;
    });
  }

  Future<bool> _ensureSpecializationSelected() async {
    final hasComboSlots = _subjects.any(
      (subject) => subject.isComboPlaceholder,
    );

    if (!hasComboSlots || _selectedCombo != null) {
      return true;
    }

    final choose = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Choose specialization first',
          ),
          content: const Text(
            'This curriculum contains specialization subjects. '
            'Choose your specialization before syncing so the '
            'generated knowledge base contains your personal study path.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'Choose specialization',
              ),
            ),
          ],
        );
      },
    );

    if (choose != true || !mounted) {
      return false;
    }

    await _chooseSpecialization();

    return _selectedCombo != null;
  }

  Future<void> _exportToObsidian({
    bool chooseNewVault = false,
  }) async {
    if (_exportingObsidian) {
      return;
    }

    final ready =
        await _ensureSpecializationSelected();

    if (!ready || !mounted) {
      return;
    }

    setState(() {
      _exportingObsidian = true;
      _exportCurrent = 0;
      _exportTotal = 0;

      _exportMessage = chooseNewVault
          ? 'Choose a new folder...'
          : _connectedVaultPath == null
              ? 'Choose your knowledge folder...'
              : 'Preparing FLM sync...';
    });

    try {
      final result =
          await _obsidianService.exportCurriculum(
        curriculumCode: widget.curriculumCode,
        curriculumSubjects: _subjects,
        specialization: _selectedCombo,
        chooseNewVault: chooseNewVault,
        onProgress: (
          current,
          total,
          message,
        ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _exportCurrent = current;
            _exportTotal = total;
            _exportMessage = message;
          });
        },
      );

      if (!mounted || result == null) {
        return;
      }

      setState(() {
        _connectedVaultPath =
            result.vaultPath;
      });

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Sync complete',
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generated ${result.exportedSubjects} '
                    'subject folders.',
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Text(
                    'Curriculum saved at:\n'
                    '${result.curriculumPath}',
                  ),

                  if (result.failedSubjects.isNotEmpty) ...[
                    const SizedBox(
                      height: 16,
                    ),
                    Text(
                      '${result.failedSubjects.length} subject(s) '
                      'could not provide detailed FLM syllabus data:',
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    Text(
                      result.failedSubjects.join(', '),
                    ),
                  ],

                  const SizedBox(
                    height: 16,
                  ),

                  const Text(
                    'Your My Notes.md files were preserved.',
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  const Text(
                    'Open this folder yourself in Obsidian whenever you want to study.',
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                  );
                },
                child: const Text(
                  'Done',
                ),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync failed: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingObsidian = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Logout?',
          ),
          content: const Text(
            'This signs out of FLM and Google inside FPT Knowledge. '
            'Your curriculum history and saved knowledge folder remain.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'Logout',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _loggingOut = true;
    });

    try {
      await AppSettings.instance.setKeepMeSignedIn(
        false,
      );

      await FlmSession.instance.logout();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              const FlmLoginScreen(),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loggingOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logout failed: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            'Could not load curriculum.\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final normalSubjects = _subjects
        .where(
          (subject) =>
              !subject.isComboPlaceholder,
        )
        .toList();

    final comboPlaceholders = _subjects
        .where(
          (subject) =>
              subject.isComboPlaceholder,
        )
        .toList();

    final semesters = <int>{};

    for (final subject in normalSubjects) {
      semesters.add(
        subject.semester,
      );
    }

    for (final placeholder
        in comboPlaceholders) {
      semesters.add(
        placeholder.semester,
      );
    }

    if (_selectedCombo != null) {
      for (final subject
          in _selectedCombo!.subjects) {
        semesters.add(
          subject.semester,
        );
      }
    }

    final semesterNumbers =
        semesters.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.curriculumCode,
        ),
        actions: [
          Tooltip(
            message:
                'Logout / Switch account',
            child: IconButton(
              onPressed:
                  _loggingOut ||
                          _exportingObsidian
                      ? null
                      : _logout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.logout,
                    ),
            ),
          ),
          const SizedBox(
            width: 8,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Curriculum Overview',
            style: Theme.of(context)
                .textTheme
                .headlineMedium,
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            '${_subjects.length} curriculum slots',
          ),

          const SizedBox(
            height: 24,
          ),

          _KnowledgeFolderCard(
            exporting:
                _exportingObsidian,
            folderPath:
                _connectedVaultPath,
            current:
                _exportCurrent,
            total:
                _exportTotal,
            message:
                _exportMessage,
            onSync: () {
              _exportToObsidian();
            },
            onChangeFolder: () {
              _exportToObsidian(
                chooseNewVault: true,
              );
            },
          ),

          const SizedBox(
            height: 24,
          ),

          for (final semester
              in semesterNumbers) ...[
            _SemesterCard(
              curriculumCode: widget.curriculumCode,
              semester: semester,
              normalSubjects:
                  normalSubjects
                      .where(
                        (subject) =>
                            subject.semester ==
                            semester,
                      )
                      .toList(),
              comboPlaceholders:
                  comboPlaceholders
                      .where(
                        (subject) =>
                            subject.semester ==
                            semester,
                      )
                      .toList(),
              selectedCombo:
                  _selectedCombo,
            ),

            if (semester == 4)
              _SpecializationCard(
                combo:
                    _selectedCombo,
                onChoose:
                    _chooseSpecialization,
              ),
          ],
        ],
      ),
    );
  }
}

class _KnowledgeFolderCard
    extends StatelessWidget {
  final bool exporting;
  final String? folderPath;
  final int current;
  final int total;
  final String message;
  final VoidCallback onSync;
  final VoidCallback onChangeFolder;

  const _KnowledgeFolderCard({
    required this.exporting,
    required this.folderPath,
    required this.current,
    required this.total,
    required this.message,
    required this.onSync,
    required this.onChangeFolder,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    double? progress;

    if (exporting && total > 0) {
      progress =
          current / total;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.folder_copy_outlined,
                  size: 34,
                ),

                const SizedBox(
                  width: 16,
                ),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        folderPath == null
                            ? 'Knowledge folder'
                            : 'Knowledge folder connected',
                        style:
                            const TextStyle(
                          fontSize: 19,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      if (folderPath == null)
                        const Text(
                          'Choose where FPT Knowledge should '
                          'generate your Markdown files.',
                        )
                      else
                        Text(
                          folderPath!,
                        ),
                    ],
                  ),
                ),

                const SizedBox(
                  width: 16,
                ),

                if (folderPath != null)
                  TextButton.icon(
                    onPressed:
                        exporting
                            ? null
                            : onChangeFolder,
                    icon: const Icon(
                      Icons.folder_open,
                    ),
                    label: const Text(
                      'Change folder',
                    ),
                  ),

                if (folderPath != null)
                  const SizedBox(
                    width: 8,
                  ),

                FilledButton.icon(
                  onPressed:
                      exporting
                          ? null
                          : onSync,
                  icon: exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.sync,
                        ),
                  label: Text(
                    folderPath == null
                        ? 'Choose folder & sync'
                        : 'Sync with FLM',
                  ),
                ),
              ],
            ),

            if (exporting) ...[
              const SizedBox(
                height: 18,
              ),

              LinearProgressIndicator(
                value: progress,
              ),

              const SizedBox(
                height: 8,
              ),

              Text(
                total > 0
                    ? '$current / $total — $message'
                    : message,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SemesterCard
    extends StatelessWidget {
  final String curriculumCode;
  final int semester;

  final List<CurriculumSubject>
      normalSubjects;

  final List<CurriculumSubject>
      comboPlaceholders;

  final SpecializationCombo?
      selectedCombo;

  const _SemesterCard({
    required this.curriculumCode,
    required this.semester,
    required this.normalSubjects,
    required this.comboPlaceholders,
    required this.selectedCombo,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final comboSubjects =
        selectedCombo?.subjects
                .where(
                  (subject) =>
                      subject.semester ==
                      semester,
                )
                .toList() ??
            [];

    return Card(
      margin: const EdgeInsets.only(
        bottom: 14,
      ),
      child: ExpansionTile(
        initiallyExpanded:
            semester == 1,
        title: Text(
          semester == 0
              ? 'Preparation / Semester 0'
              : 'Semester $semester',
        ),
        subtitle: Text(
          '${normalSubjects.length + comboSubjects.length} subjects',
        ),
        children: [
          for (final subject
              in normalSubjects)
            ListTile(
              title: Text(
                subject.code,
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              subtitle:
                  Text(subject.name),
              trailing: Row(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Text(
                    '${subject.credits} cr',
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  const Icon(
                    Icons.chevron_right,
                  ),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SubjectDetailScreen(
                      curriculumCode: curriculumCode,
                      subject: subject,
                    ),
                  ),
                );
              },
            ),

          if (selectedCombo == null &&
              comboPlaceholders.isNotEmpty)
            const ListTile(
              leading: Icon(
                Icons.route_outlined,
              ),
              title: Text(
                'Specialization subject',
              ),
              subtitle: Text(
                'Choose your specialization after Semester 4.',
              ),
            ),

          if (selectedCombo != null)
            for (final comboSubject
                in comboSubjects)
              ListTile(
                leading: const Icon(
                  Icons.route_outlined,
                ),
                title: Text(
                  comboSubject.code,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                subtitle:
                    Text(
                  comboSubject.name,
                ),
                trailing: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: const [
                    Chip(
                      label: Text(
                        'Specialization',
                      ),
                    ),
                    SizedBox(
                      width: 8,
                    ),
                    Icon(
                      Icons.chevron_right,
                    ),
                  ],
                ),
                onTap: () {
                  final subject =
                      CurriculumSubject(
                    code:
                        comboSubject.code,
                    name:
                        comboSubject.name,
                    semester:
                        comboSubject.semester,
                    credits: 0,
                    prerequisite: '',
                  );

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SubjectDetailScreen(
                        curriculumCode: curriculumCode,
                        subject: subject,
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _SpecializationCard
    extends StatelessWidget {
  final SpecializationCombo? combo;
  final VoidCallback onChoose;

  const _SpecializationCard({
    required this.combo,
    required this.onChoose,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Card(
      margin: const EdgeInsets.only(
        bottom: 18,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.route_outlined,
                  size: 30,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Text(
                    combo == null
                        ? 'Choose your specialization'
                        : 'Your specialization',
                    style:
                        const TextStyle(
                      fontSize: 21,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 12,
            ),

            if (combo == null)
              const Text(
                'Your specialization subjects begin after '
                'this stage. Choose a career path and we '
                'will place its real FLM subjects into the '
                'correct semesters.',
              )
            else ...[
              Text(
                combo!.name,
                style:
                    const TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              for (final subject
                  in combo!.subjects)
                Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 5,
                  ),
                  child: Text(
                    'Semester ${subject.semester}  •  '
                    '${subject.code}  •  '
                    '${subject.name}',
                  ),
                ),
            ],

            const SizedBox(
              height: 18,
            ),

            FilledButton.icon(
              onPressed: onChoose,
              icon: Icon(
                combo == null
                    ? Icons.route_outlined
                    : Icons.edit_outlined,
              ),
              label: Text(
                combo == null
                    ? 'Choose specialization'
                    : 'Change specialization',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
