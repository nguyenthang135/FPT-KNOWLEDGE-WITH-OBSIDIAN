import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_repository.dart';
import '../flm/flm_combo_service.dart';
import '../flm/flm_session.dart';
import '../models/curriculum_subject.dart';
import '../notes/json_markdown_export_service.dart';
import '../obsidian/obsidian_service.dart';
import '../search/curriculum_search.dart';
import '../settings/app_settings.dart';
import '../widgets/workspace_sidebar.dart';
import 'combo_selection_screen.dart';
import 'flm_login_screen.dart';
import 'my_notes_view.dart';
import 'subject_detail_screen.dart';

class CurriculumOverviewScreen extends StatefulWidget {
  final String curriculumCode;

  const CurriculumOverviewScreen({super.key, required this.curriculumCode});

  @override
  State<CurriculumOverviewScreen> createState() =>
      _CurriculumOverviewScreenState();
}

class _CurriculumOverviewScreenState extends State<CurriculumOverviewScreen> {
  bool _loading = true;
  bool _loggingOut = false;
  bool _exportingObsidian = false;

  String? _error;

  List<CurriculumSubject> _subjects = [];

  SpecializationCombo? _selectedCombo;

  final ObsidianService _obsidianService = ObsidianService();
  late final Future<DatabaseRepository> _databaseRepository;

  String? _connectedVaultPath;

  final TextEditingController _searchController = TextEditingController();

  WorkspaceSection _selectedSection = WorkspaceSection.curriculum;

  String _searchQuery = '';

  String? _completedNotesSyncSignature;
  @override
  void initState() {
    super.initState();

    _databaseRepository = _loadDatabaseRepository();
    _restoreVault();
    _loadSubjects();
  }

  Future<DatabaseRepository> _loadDatabaseRepository() async {
    final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
    final repository = DatabaseRepository(
      Directory(
        '$appData${Platform.pathSeparator}FPT Knowledge'
        '${Platform.pathSeparator}Database',
      ),
    );
    await repository.initialize();
    return repository;
  }

  Future<void> _restoreVault() async {
    final path = await _obsidianService.getSavedVaultPath();

    if (!mounted) {
      return;
    }

    setState(() {
      _connectedVaultPath = path;
    });
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await FlmSession.instance.getCurriculumSubjects();
      final savedSpecialization = await AppSettings.instance.getSpecialization(
        widget.curriculumCode,
      );

      if (!mounted) {
        return;
      }

      final hasComboSlots = subjects.any(
        (subject) => subject.isComboPlaceholder,
      );

      setState(() {
        _subjects = subjects;
        _selectedCombo = hasComboSlots ? savedSpecialization : null;
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

  Future<void> _chooseSpecialization({bool syncAfterSelection = true}) async {
    final combo = await Navigator.of(context).push<SpecializationCombo>(
      MaterialPageRoute(
        builder: (_) =>
            ComboSelectionScreen(curriculumCode: widget.curriculumCode),
      ),
    );

    if (combo == null || !mounted) {
      return;
    }

    setState(() {
      _selectedCombo = combo;
      _completedNotesSyncSignature = null;
    });

    try {
      await AppSettings.instance.setSpecialization(
        widget.curriculumCode,
        combo,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remember specialization: $error')),
        );
      }
    }

    if (syncAfterSelection && _connectedVaultPath != null && mounted) {
      await _exportToObsidian(forceRefresh: true);
    }
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
          title: const Text('Choose specialization first'),
          content: const Text(
            'This curriculum contains specialization subjects. '
            'Choose your specialization before syncing so the '
            'generated knowledge base contains your personal study path.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Choose specialization'),
            ),
          ],
        );
      },
    );

    if (choose != true || !mounted) {
      return false;
    }

    await _chooseSpecialization(syncAfterSelection: false);

    return _selectedCombo != null;
  }

  Future<bool> _exportToObsidian({
    bool chooseNewVault = false,
    bool showCompletionDialog = true,
    bool automatic = false,
    bool forceRefresh = false,
  }) async {
    if (_exportingObsidian) {
      return false;
    }

    if (automatic &&
        !forceRefresh &&
        _completedNotesSyncSignature == _notesSyncSignature &&
        _connectedVaultPath != null) {
      return true;
    }

    if (!FlmSession.instance.isAuthenticated) {
      return false;
    }

    final ready = await _ensureSpecializationSelected();

    if (!ready || !mounted) {
      return false;
    }

    setState(() {
      _exportingObsidian = true;
    });

    try {
      await FlmSession.instance.searchCurriculum(widget.curriculumCode);

      await FlmSession.instance.openCurriculumByCode(widget.curriculumCode);

      final refreshedSubjects = await FlmSession.instance
          .getCurriculumSubjects();

      if (!mounted) {
        return false;
      }

      setState(() {
        _subjects = refreshedSubjects;
      });

      final result = await _obsidianService.exportCurriculum(
        curriculumCode: widget.curriculumCode,
        curriculumSubjects: refreshedSubjects,
        specialization: _selectedCombo,
        chooseNewVault: chooseNewVault,
      );

      if (!mounted || result == null) {
        return false;
      }

      setState(() {
        _connectedVaultPath = result.vaultPath;
        _completedNotesSyncSignature = _notesSyncSignature;
      });

      if (showCompletionDialog) {
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Sync complete'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generated ${result.exportedSubjects} '
                      'subject folders.',
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Curriculum saved at:\n'
                      '${result.curriculumPath}',
                    ),

                    if (result.failedSubjects.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        '${result.failedSubjects.length} subject(s) '
                        'could not provide detailed FLM syllabus data:',
                      ),
                      const SizedBox(height: 6),
                      Text(result.failedSubjects.join(', ')),
                    ],

                    const SizedBox(height: 16),

                    const Text('Your My Notes.md files were preserved.'),

                    const SizedBox(height: 12),

                    const Text(
                      'Open this folder yourself in Obsidian whenever you want to study.',
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      }

      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      if (!automatic) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $error')));
      }

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _exportingObsidian = false;
        });
      }
    }
  }

  String get _notesSyncSignature {
    final codes =
        _selectedCombo?.subjects
            .map((subject) => subject.code.trim().toUpperCase())
            .toList() ??
        <String>[];

    codes.sort();

    return '${widget.curriculumCode.trim().toUpperCase()}|'
        '${_selectedCombo?.name.trim().toLowerCase() ?? ''}|'
        '${codes.join(',')}';
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout?'),
          content: const Text(
            'This signs out of FLM and Google inside FPT Knowledge. '
            'Your curriculum history and saved knowledge folder remain.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Logout'),
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
      await AppSettings.instance.setKeepMeSignedIn(false);

      await FlmSession.instance.logout();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const FlmLoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loggingOut = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $error')));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.curriculumCode),
        actions: [
          Tooltip(
            message: 'Logout / Switch account',
            child: IconButton(
              onPressed: _loggingOut || _exportingObsidian ? null : _logout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidebarWidth = constraints.maxWidth < 900 ? 200.0 : 240.0;

          return Row(
            children: [
              Expanded(child: _buildWorkspaceContent()),
              WorkspaceSidebar(
                width: sidebarWidth,
                selectedSection: _selectedSection,
                onSelected: (section) {
                  setState(() {
                    _selectedSection = section;
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWorkspaceContent() {
    switch (_selectedSection) {
      case WorkspaceSection.curriculum:
        return _buildCurriculumContent();
      case WorkspaceSection.notes:
        return _buildNotesContent();
      case WorkspaceSection.askFlm:
        return _buildAskFlmContent();
    }
  }

  Widget _buildCurriculumContent() {
    final normalSubjects = _subjects
        .where((subject) => !subject.isComboPlaceholder)
        .toList();

    final comboPlaceholders = _subjects
        .where((subject) => subject.isComboPlaceholder)
        .toList();

    final semesters = <int>{
      ...normalSubjects.map((subject) => subject.semester),
      ...comboPlaceholders.map((subject) => subject.semester),
      ...?_selectedCombo?.subjects.map((subject) => subject.semester),
    };

    final semesterNumbers = semesters.toList()..sort();
    final normalizedQuery = normalizeCurriculumSearchText(_searchQuery);
    final searchActive = normalizedQuery.isNotEmpty;
    final semesterWidgets = <Widget>[];

    for (final semester in semesterNumbers) {
      final semesterMatch =
          searchActive &&
          semesterMatchesCurriculumQuery(semester, normalizedQuery);

      final semesterNormalSubjects = normalSubjects
          .where((subject) => subject.semester == semester)
          .toList();
      final semesterPlaceholders = comboPlaceholders
          .where((subject) => subject.semester == semester)
          .toList();
      final semesterComboSubjects =
          _selectedCombo?.subjects
              .where((subject) => subject.semester == semester)
              .toList() ??
          <ComboSubject>[];

      final visibleNormalSubjects = !searchActive || semesterMatch
          ? semesterNormalSubjects
          : semesterNormalSubjects
                .where(
                  (subject) =>
                      curriculumSubjectMatchesQuery(subject, normalizedQuery),
                )
                .toList();
      final visiblePlaceholders = !searchActive || semesterMatch
          ? semesterPlaceholders
          : semesterPlaceholders
                .where(
                  (subject) =>
                      curriculumSubjectMatchesQuery(subject, normalizedQuery),
                )
                .toList();
      final visibleComboSubjects = !searchActive || semesterMatch
          ? semesterComboSubjects
          : semesterComboSubjects
                .where(
                  (subject) =>
                      comboSubjectMatchesQuery(subject, normalizedQuery),
                )
                .toList();

      if (visibleNormalSubjects.isEmpty &&
          visiblePlaceholders.isEmpty &&
          visibleComboSubjects.isEmpty) {
        continue;
      }

      semesterWidgets.add(
        _SemesterCard(
          key: ValueKey('semester-$semester-$normalizedQuery'),
          semester: semester,
          normalSubjects: visibleNormalSubjects,
          comboPlaceholders: visiblePlaceholders,
          selectedCombo: _selectedCombo,
          visibleComboSubjects: visibleComboSubjects,
          forceExpanded: searchActive,
        ),
      );

      if (!searchActive && semester == 4) {
        semesterWidgets.add(
          _SpecializationCard(
            combo: _selectedCombo,
            onChoose: () => _chooseSpecialization(),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'My Curriculum',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text('${_subjects.length} curriculum slots'),
        const SizedBox(height: 20),
        TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          decoration: InputDecoration(
            hintText: 'Search subjects or semesters...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchActive
                ? IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                    icon: const Icon(Icons.clear),
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        if (semesterWidgets.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(Icons.search_off_outlined, size: 38),
                  const SizedBox(height: 12),
                  Text(
                    'No subjects or semesters match “${_searchQuery.trim()}”.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ...semesterWidgets,
      ],
    );
  }

  Widget _buildNotesContent() {
    return FutureBuilder<DatabaseRepository>(
      future: _databaseRepository,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not open local database: ${snapshot.error}'),
          );
        }
        final repository = snapshot.data;
        if (repository == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return MyNotesView(
          exportService: JsonMarkdownExportService(repository),
          folderPath: _connectedVaultPath,
          onChooseFolder: () async {
            final path = await _obsidianService.chooseVault();
            if (path != null && mounted) {
              setState(() => _connectedVaultPath = path);
            }
            return path;
          },
        );
      },
    );
  }

  Widget _buildAskFlmContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 46),
                  SizedBox(height: 16),
                  Text(
                    'Ask FLM',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Grounded questions and answers from synchronized FLM data will be added in Phase 4.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SemesterCard extends StatelessWidget {
  final int semester;

  final List<CurriculumSubject> normalSubjects;

  final List<CurriculumSubject> comboPlaceholders;

  final SpecializationCombo? selectedCombo;

  final List<ComboSubject>? visibleComboSubjects;

  final bool forceExpanded;

  const _SemesterCard({
    super.key,
    required this.semester,
    required this.normalSubjects,
    required this.comboPlaceholders,
    required this.selectedCombo,
    this.visibleComboSubjects,
    this.forceExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final comboSubjects =
        visibleComboSubjects ??
        selectedCombo?.subjects
            .where((subject) => subject.semester == semester)
            .toList() ??
        [];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        initiallyExpanded: forceExpanded || semester == 1,
        title: Text(
          semester == 0 ? 'Preparation / Semester 0' : 'Semester $semester',
        ),
        subtitle: Text(
          '${normalSubjects.length + comboSubjects.length} subjects',
        ),
        children: [
          for (final subject in normalSubjects)
            ListTile(
              title: Text(
                subject.code,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(subject.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${subject.credits} cr'),
                  const SizedBox(width: 12),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubjectDetailScreen(subject: subject),
                  ),
                );
              },
            ),

          if (selectedCombo == null && comboPlaceholders.isNotEmpty)
            const ListTile(
              leading: Icon(Icons.route_outlined),
              title: Text('Specialization subject'),
              subtitle: Text('Choose your specialization after Semester 4.'),
            ),

          if (selectedCombo != null)
            for (final comboSubject in comboSubjects)
              ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(
                  comboSubject.code,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(comboSubject.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Chip(label: Text('Specialization')),
                    SizedBox(width: 8),
                    Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () {
                  final subject = CurriculumSubject(
                    code: comboSubject.code,
                    name: comboSubject.name,
                    semester: comboSubject.semester,
                    credits: 0,
                    prerequisite: '',
                  );

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SubjectDetailScreen(subject: subject),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _SpecializationCard extends StatelessWidget {
  final SpecializationCombo? combo;
  final VoidCallback onChoose;

  const _SpecializationCard({required this.combo, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_outlined, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    combo == null
                        ? 'Choose your specialization'
                        : 'Your specialization',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 12),

              for (final subject in combo!.subjects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    'Semester ${subject.semester}  •  '
                    '${subject.code}  •  '
                    '${subject.name}',
                  ),
                ),
            ],

            const SizedBox(height: 18),

            FilledButton.icon(
              onPressed: onChoose,
              icon: Icon(
                combo == null ? Icons.route_outlined : Icons.edit_outlined,
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
