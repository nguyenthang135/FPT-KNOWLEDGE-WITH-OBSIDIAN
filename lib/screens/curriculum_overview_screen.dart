import 'dart:io';
import 'package:flutter/material.dart';

import '../flm/flm_combo_service.dart';
import '../flm/flm_session.dart';
import '../models/curriculum_subject.dart';
import '../obsidian/obsidian_service.dart';
import '../settings/app_settings.dart';
import '../design_system/app_shell.dart';
import '../design_system/app_theme.dart';
import '../design_system/app_widgets.dart';
import '../design_system/fpt_loading.dart';
import 'combo_selection_screen.dart';
import 'flm_login_screen.dart';
import 'subject_detail_screen.dart';

class CurriculumOverviewScreen extends StatefulWidget {
  final String curriculumCode;
  final String? preferredCombo;

  const CurriculumOverviewScreen({
    super.key,
    required this.curriculumCode,
    this.preferredCombo,
  });

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

  String? _connectedVaultPath;

  int _exportCurrent = 0;
  int _exportTotal = 0;
  String _exportMessage = '';
  DateTime? _lastSync;

  final TextEditingController _subjectSearchController = TextEditingController();
  String _subjectSearchQuery = '';

  @override
  void initState() {
    super.initState();

    _restoreVault();
    _loadSubjects();
  }

  @override
  void dispose() {
    _subjectSearchController.dispose();
    super.dispose();
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
    final startTime = DateTime.now();
    try {
      final subjects = await FlmSession.instance.getCurriculumSubjects();

      final elapsed = DateTime.now().difference(startTime);
      const minDuration = Duration(milliseconds: 3500);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _subjects = subjects;
        _loading = false;
      });

      if (widget.preferredCombo != null && _selectedCombo == null) {
        _tryAutoSelectCombo(widget.preferredCombo!);
      }
    } catch (error) {
      final elapsed = DateTime.now().difference(startTime);
      const minDuration = Duration(milliseconds: 2500);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _tryAutoSelectCombo(String comboName) async {
    try {
      final service = FlmComboService();
      final options = await service.loadAvailableCombos(widget.curriculumCode);
      final norm = comboName.trim().toUpperCase();
      final matched = options.where((opt) => opt.name.toUpperCase().contains(norm)).toList();
      if (matched.isNotEmpty) {
        final combo = await service.loadCombo(matched.first);
        if (mounted) {
          setState(() {
            _selectedCombo = combo;
          });
        }
      }
    } catch (e) {
      debugPrint('Auto-select combo error: $e');
    }
  }

  Future<void> _chooseSpecialization() async {
    final combo = await showGeneralDialog<SpecializationCombo>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close specialization panel',
      barrierColor: const Color(0x660F172A),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        final width = MediaQuery.sizeOf(dialogContext).width;
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: width < 600 ? width : 520,
              height: double.infinity,
              child: Material(
                color: AppColors.surface,
                elevation: 18,
                child: ComboSelectionScreen(
                  curriculumCode: widget.curriculumCode,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
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

    await _chooseSpecialization();

    return _selectedCombo != null;
  }

  Future<void> _exportToObsidian({bool chooseNewVault = false}) async {
    if (_exportingObsidian) {
      return;
    }

    final ready = await _ensureSpecializationSelected();

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
      final result = await _obsidianService.exportCurriculum(
        curriculumCode: widget.curriculumCode,
        curriculumSubjects: _subjects,
        specialization: _selectedCombo,
        chooseNewVault: chooseNewVault,
        onProgress: (current, total, message) {
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
        _connectedVaultPath = result.vaultPath;
        _lastSync = DateTime.now();
      });

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
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _exportingObsidian = false;
        });
      }
    }
  }

  Future<void> _openFolder() async {
    final path = _connectedVaultPath;
    if (path == null) return;
    try {
      await Process.start('explorer.exe', [
        path,
      ], mode: ProcessStartMode.detached);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open folder: $error')),
        );
      }
    }
  }

  Future<void> _logout() async {
    if (_loggingOut || _exportingObsidian) {
      return;
    }

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
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: FptTechLoading(
          title: widget.curriculumCode,
          subtitle: 'Syncing curriculum structure from FPT FLM...',
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
        .where((subject) => !subject.isComboPlaceholder)
        .toList();

    final comboPlaceholders = _subjects
        .where((subject) => subject.isComboPlaceholder)
        .toList();

    final query = _subjectSearchQuery.trim().toLowerCase();

    final filteredNormalSubjects = normalSubjects.where((subject) {
      if (query.isEmpty) return true;
      return subject.code.toLowerCase().contains(query) ||
          subject.name.toLowerCase().contains(query) ||
          'kỳ ${subject.semester}'.contains(query) ||
          'semester ${subject.semester}'.contains(query);
    }).toList();

    final filteredComboPlaceholders = comboPlaceholders.where((subject) {
      if (query.isEmpty) return true;
      return subject.code.toLowerCase().contains(query) ||
          subject.name.toLowerCase().contains(query) ||
          'kỳ ${subject.semester}'.contains(query) ||
          'semester ${subject.semester}'.contains(query);
    }).toList();

    final filteredComboSubjects = _selectedCombo?.subjects.where((subject) {
      if (query.isEmpty) return true;
      return subject.code.toLowerCase().contains(query) ||
          subject.name.toLowerCase().contains(query) ||
          'kỳ ${subject.semester}'.contains(query) ||
          'semester ${subject.semester}'.contains(query);
    }).toList();

    final semesters = <int>{};
    for (final subject in normalSubjects) {
      semesters.add(subject.semester);
    }
    for (final placeholder in comboPlaceholders) {
      semesters.add(placeholder.semester);
    }
    if (_selectedCombo != null) {
      for (final subject in _selectedCombo!.subjects) {
        semesters.add(subject.semester);
      }
    }
    final semesterNumbers = semesters.toList()..sort();

    final activeSemesters = <int>{};
    for (final subject in filteredNormalSubjects) {
      activeSemesters.add(subject.semester);
    }
    for (final placeholder in filteredComboPlaceholders) {
      activeSemesters.add(placeholder.semester);
    }
    if (filteredComboSubjects != null) {
      for (final subject in filteredComboSubjects) {
        activeSemesters.add(subject.semester);
      }
    }
    final displaySemesterNumbers = query.isEmpty
        ? semesterNumbers
        : (activeSemesters.toList()..sort());

    final parts = widget.curriculumCode.split('_');
    final program = parts.length > 1
        ? parts.take(parts.length - 1).join('_')
        : widget.curriculumCode;
    final intake = parts.length > 1 ? parts.last : '—';
    final credits = normalSubjects.fold<int>(
      0,
      (sum, item) => sum + item.credits,
    );

    final totalMatchedSubjects = filteredNormalSubjects.length +
        filteredComboPlaceholders.length +
        (filteredComboSubjects?.length ?? 0);

    return AppShell(
      title: 'Curriculum',
      selectedIndex: 0,
      onLogout: _logout,
      isLoggingOut: _loggingOut,
      child: ListView(
        children: [
          MaxWidthContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 20,
                  runSpacing: 16,
                  children: [
                    const SizedBox(
                      width: 700,
                      child: PageHeading(
                        eyebrow: 'Curriculum workspace',
                        title: 'Curriculum overview',
                        subtitle:
                            'Review your study path and keep your Obsidian knowledge workspace in sync.',
                      ),
                    ),
                    if (comboPlaceholders.isNotEmpty)
                      SecondaryButton(
                        label: _selectedCombo == null
                            ? 'Choose specialization'
                            : 'Change specialization',
                        icon: _selectedCombo == null
                            ? Icons.route_outlined
                            : Icons.edit_outlined,
                        onPressed: _chooseSpecialization,
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeaderStat(
                      label: 'CURRICULUM',
                      value: widget.curriculumCode,
                      mono: true,
                    ),
                    _HeaderStat(label: 'PROGRAM', value: program),
                    _HeaderStat(label: 'INTAKE', value: intake),
                    _HeaderStat(
                      label: 'SUBJECTS',
                      value: '${normalSubjects.length}',
                    ),
                    _HeaderStat(
                      label: 'SEMESTERS',
                      value: '${semesterNumbers.length}',
                    ),
                    if (credits > 0)
                      _HeaderStat(label: 'CREDITS', value: '$credits'),
                  ],
                ),
                const SizedBox(height: 28),
                _KnowledgeFolderCard(
                  exporting: _exportingObsidian,
                  folderPath: _connectedVaultPath,
                  current: _exportCurrent,
                  total: _exportTotal,
                  message: _exportMessage,
                  lastSync: _lastSync,
                  onSync: _exportToObsidian,
                  onOpenFolder: _openFolder,
                  onChangeFolder: () => _exportToObsidian(chooseNewVault: true),
                ),
                const SizedBox(height: 30),
                if (_selectedCombo != null) ...[
                  _SpecializationCard(combo: _selectedCombo!),
                  const SizedBox(height: 12),
                ],

                // Subject search bar
                TextField(
                  controller: _subjectSearchController,
                  onChanged: (val) => setState(() => _subjectSearchQuery = val),
                  decoration: InputDecoration(
                    labelText: 'Tìm kiếm môn học',
                    hintText: 'Mã môn (PRJ301, PRO192...), tên môn (Java...), hoặc kỳ học...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _subjectSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            tooltip: 'Xóa tìm kiếm',
                            onPressed: () {
                              _subjectSearchController.clear();
                              setState(() => _subjectSearchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
                if (_subjectSearchQuery.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Tìm thấy $totalMatchedSubjects môn học',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () {
                          _subjectSearchController.clear();
                          setState(() => _subjectSearchQuery = '');
                        },
                        child: const Text('Xóa bộ lọc', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Study plan',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      '${displaySemesterNumbers.length} / ${semesterNumbers.length} semesters',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (displaySemesterNumbers.isEmpty && _subjectSearchQuery.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'Không tìm thấy môn học nào khớp với "$_subjectSearchQuery"',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Thử tìm theo mã môn (vd: PRJ, PRO, MAS) hoặc tên môn học.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                for (final semester in displaySemesterNumbers)
                  _SemesterCard(
                    curriculumCode: widget.curriculumCode,
                    semester: semester,
                    isSearching: _subjectSearchQuery.isNotEmpty,
                    normalSubjects: filteredNormalSubjects
                        .where((subject) => subject.semester == semester)
                        .toList(),
                    comboPlaceholders: filteredComboPlaceholders
                        .where((subject) => subject.semester == semester)
                        .toList(),
                    filteredComboSubjects: filteredComboSubjects
                        ?.where((subject) => subject.semester == semester)
                        .toList(),
                    selectedCombo: _selectedCombo,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.label,
    required this.value,
    this.mono = false,
  });
  final String label, value;
  final bool mono;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label  ',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: .7,
          ),
        ),
        Text(
          value,
          style: (mono ? monoStyle : const TextStyle()).copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

class _KnowledgeFolderCard extends StatelessWidget {
  final bool exporting;
  final String? folderPath;
  final int current;
  final int total;
  final String message;
  final DateTime? lastSync;
  final VoidCallback onSync;
  final VoidCallback onOpenFolder;
  final VoidCallback onChangeFolder;

  const _KnowledgeFolderCard({
    required this.exporting,
    required this.folderPath,
    required this.current,
    required this.total,
    required this.message,
    required this.lastSync,
    required this.onSync,
    required this.onOpenFolder,
    required this.onChangeFolder,
  });

  @override
  Widget build(BuildContext context) {
    double? progress;

    if (exporting && total > 0) {
      progress = current / total;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.hub_outlined,
                  size: 30,
                  color: AppColors.purple,
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Knowledge workspace',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 5),

                      if (folderPath == null)
                        const Text(
                          'Connect an Obsidian vault to generate and synchronize your study notes.',
                        )
                      else
                        Text(
                          folderPath!,
                          style: monoStyle.copyWith(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),
              ],
            ),

            const SizedBox(height: 18),
            if (folderPath == null)
              Align(
                alignment: Alignment.centerLeft,
                child: PrimaryButton(
                  label: 'Connect folder',
                  icon: Icons.add_link,
                  loading: exporting,
                  onPressed: onChangeFolder,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    exporting ? 'Synchronizing' : 'Connected',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  Text(
                    lastSync == null
                        ? 'Not synced yet'
                        : 'Last sync ${lastSync!.hour.toString().padLeft(2, '0')}:${lastSync!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  GhostButton(
                    label: 'Change',
                    icon: Icons.drive_folder_upload_outlined,
                    onPressed: exporting ? null : onChangeFolder,
                  ),
                  SecondaryButton(
                    label: 'Open folder',
                    icon: Icons.folder_open_outlined,
                    onPressed: exporting ? null : onOpenFolder,
                  ),
                  PrimaryButton(
                    label: 'Sync now',
                    icon: Icons.sync,
                    loading: exporting,
                    onPressed: onSync,
                  ),
                ],
              ),

            if (exporting) ...[
              const SizedBox(height: 18),

              LinearProgressIndicator(value: progress),

              const SizedBox(height: 8),

              Text(total > 0 ? '$current / $total — $message' : message),
            ],
          ],
        ),
      ),
    );
  }
}

class _SemesterCard extends StatelessWidget {
  final String curriculumCode;

  final int semester;

  final List<CurriculumSubject> normalSubjects;

  final List<CurriculumSubject> comboPlaceholders;

  final SpecializationCombo? selectedCombo;

  final bool isSearching;

  final List<ComboSubject>? filteredComboSubjects;

  const _SemesterCard({
    required this.curriculumCode,
    required this.semester,
    required this.normalSubjects,
    required this.comboPlaceholders,
    required this.selectedCombo,
    this.isSearching = false,
    this.filteredComboSubjects,
  });

  @override
  Widget build(BuildContext context) {
    final comboSubjects = filteredComboSubjects ??
        (selectedCombo?.subjects
            .where((subject) => subject.semester == semester)
            .toList() ??
        []);
    final totalCredits = normalSubjects.fold<int>(
      0,
      (sum, subject) => sum + subject.credits,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        initiallyExpanded: isSearching || semester == 1,
        title: Text(
          semester == 0 ? 'Preparation / Semester 0' : 'Semester $semester',
        ),
        subtitle: Text(
          '${normalSubjects.length + comboSubjects.length} subjects${totalCredits > 0 ? '  ·  $totalCredits credits' : ''}',
        ),
        children: [
          for (final subject in normalSubjects)
            _SubjectRow(
              subject: subject,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubjectDetailScreen(
                      curriculumCode: curriculumCode,
                      subject: subject,
                    ),
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
                      builder: (_) => SubjectDetailScreen(
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

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.subject, required this.onTap});
  final CurriculumSubject subject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final names = subject.name.split('_');
    final english = names.first.trim();
    final vietnamese = names.length > 1
        ? names.sublist(1).join('_').trim()
        : '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  subject.code,
                  style: monoStyle.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      english,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (vietnamese.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        vietnamese,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (subject.credits > 0)
                Text(
                  '${subject.credits} cr',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpecializationCard extends StatelessWidget {
  final SpecializationCombo combo;

  const _SpecializationCard({required this.combo});

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
                    'Your specialization',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            ...[
              Text(
                combo.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 12),

              for (final subject in combo.subjects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    'Semester ${subject.semester}  •  '
                    '${subject.code}  •  '
                    '${subject.name}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
