import 'dart:async';
import 'package:flutter/material.dart';

import '../ai/ask_fpt_controller.dart';
import '../database/database_repository.dart';
import '../notes/json_markdown_export_service.dart';
import '../obsidian/obsidian_service.dart';
import '../settings/app_settings.dart';
import 'ask_fpt_screen.dart';
import 'database_curriculum_detail_screen.dart';
import 'database_subject_detail_screen.dart';
import 'flm_login_screen.dart';
import 'my_notes_view.dart';

enum StudentSection { database, curriculum, notes, askFpt }

class StudentHomeScreen extends StatefulWidget {
  final DatabaseRepository repository;

  const StudentHomeScreen({super.key, required this.repository});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  StudentSection _section = StudentSection.askFpt;
  String? _currentCurriculum;
  List<DatabaseCurriculum> _savedCurricula = const [];
  bool _checkingCurriculum = true;
  late final AskFptController _askFptController;
  late final JsonMarkdownExportService _exportService;
  final ObsidianService _obsidianService = ObsidianService();
  String? _vaultPath;
  String? _notesFocusItemId;
  String? _notesOpenItemId;

  @override
  void initState() {
    super.initState();
    _askFptController = AskFptController(widget.repository);
    _exportService = JsonMarkdownExportService(widget.repository);
    _initialize();
  }

  Future<void> _initialize() async {
    await _askFptController.initialize();
    await _refreshCurrentCurriculum();
  }

  @override
  void dispose() {
    _askFptController.dispose();
    super.dispose();
  }

  Future<void> _refreshCurrentCurriculum() async {
    final saved = await AppSettings.instance.getCurrentCurriculum();
    final valid =
        saved != null && await widget.repository.containsCurriculum(saved);
    if (saved != null && !valid) {
      await AppSettings.instance.setCurrentCurriculum(null);
    }
    final history = await AppSettings.instance.getCurriculumHistory();
    final curricula = <DatabaseCurriculum>[];
    for (final code in history) {
      final curriculum = await widget.repository.loadCurriculum(code);
      if (curriculum != null) curricula.add(curriculum);
    }
    final vaultPath = await _obsidianService.getSavedVaultPath();
    _askFptController.activeProvenance = await AppSettings.instance
        .getActiveContextProvenance();
    final hasExplicitContext =
        _askFptController.activeProvenance != ActiveContextProvenance.none;
    await _askFptController.adoptActiveCurriculum(
      valid && hasExplicitContext ? saved : null,
    );
    if (!mounted) return;
    setState(() {
      _currentCurriculum = valid && hasExplicitContext ? saved : null;
      _savedCurricula = curricula;
      _vaultPath = vaultPath;
      _checkingCurriculum = false;
    });
  }

  Future<String?> _chooseNotesFolder() async {
    final path = await _obsidianService.chooseVault();
    if (path != null && mounted) setState(() => _vaultPath = path);
    return path;
  }

  Future<void> _useCurriculum(String code) async {
    await _askFptController.selectActiveCurriculum(code);
    await _refreshCurrentCurriculum();
  }

  Future<void> _removeCurriculum(String code) async {
    await AppSettings.instance.removeCurriculum(code);
    await _refreshCurrentCurriculum();
  }

  Future<void> _viewCurriculum(String code) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DatabaseCurriculumDetailScreen(
          repository: widget.repository,
          curriculumCode: code,
          showUseAction: false,
          onSelectionChanged: _refreshCurrentCurriculum,
        ),
      ),
    );
    await _refreshCurrentCurriculum();
  }

  void _showNotesItem(String itemId, {required bool open}) {
    setState(() {
      _section = StudentSection.notes;
      _notesFocusItemId = open ? null : itemId;
      _notesOpenItemId = open ? itemId : null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('FPT Knowledge'),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const FlmLoginScreen())),
          icon: const Icon(Icons.admin_panel_settings_outlined),
          label: const Text('Connect to FLM'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(child: _content()),
          _StudentSidebar(
            width: constraints.maxWidth < 900 ? 205 : 240,
            selected: _section,
            onSelected: (value) => setState(() => _section = value),
          ),
        ],
      ),
    ),
  );

  Widget _content() => switch (_section) {
    StudentSection.askFpt => AskFptScreen(
      controller: _askFptController,
      onBrowseDatabase: () =>
          setState(() => _section = StudentSection.database),
      onOpenCurriculum: () =>
          setState(() => _section = StudentSection.curriculum),
      onOpenNotes: () => setState(() => _section = StudentSection.notes),
      onProfileChanged: _refreshCurrentCurriculum,
      onViewMyNotesItem: (itemId) => _showNotesItem(itemId, open: false),
      onOpenMyNotesItem: (itemId) => _showNotesItem(itemId, open: true),
    ),
    StudentSection.database => _DatabaseBrowser(
      repository: widget.repository,
      onCurriculumSelected: _refreshCurrentCurriculum,
    ),
    StudentSection.curriculum => _myCurriculum(),
    StudentSection.notes => _myNotes(),
  };

  Widget _myNotes() {
    if (_checkingCurriculum) {
      return const Center(child: CircularProgressIndicator());
    }
    return MyNotesView(
      exportService: _exportService,
      folderPath: _vaultPath,
      onChooseFolder: _chooseNotesFolder,
      focusItemId: _notesFocusItemId,
      openItemId: _notesOpenItemId,
      onItemRequestHandled: () {
        if (!mounted) return;
        setState(() {
          _notesFocusItemId = null;
          _notesOpenItemId = null;
        });
      },
    );
  }

  Widget _myCurriculum() {
    if (_checkingCurriculum) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Curriculum',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Saved curricula stay here. Only one is active at a time.',
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () =>
                  setState(() => _section = StudentSection.database),
              icon: const Icon(Icons.add),
              label: const Text('Add / Find curriculum'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (_savedCurricula.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.school_outlined),
              title: Text('No saved curricula'),
              subtitle: Text(
                'Find one in Database and choose Use this curriculum.',
              ),
            ),
          )
        else
          for (final curriculum in _savedCurricula)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  curriculum.code,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              if (_currentCurriculum == curriculum.code) ...[
                                const SizedBox(width: 8),
                                const Chip(label: Text('ACTIVE')),
                              ],
                            ],
                          ),
                          if (curriculum.name.isNotEmpty) Text(curriculum.name),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _viewCurriculum(curriculum.code),
                      child: const Text('View'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _currentCurriculum == curriculum.code
                          ? null
                          : () => _useCurriculum(curriculum.code),
                      child: const Text('Use'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _removeCurriculum(curriculum.code),
                      child: const Text('Remove from My Curriculum'),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _DatabaseBrowser extends StatefulWidget {
  final DatabaseRepository repository;
  final VoidCallback onCurriculumSelected;

  const _DatabaseBrowser({
    required this.repository,
    required this.onCurriculumSelected,
  });

  @override
  State<_DatabaseBrowser> createState() => _DatabaseBrowserState();
}

class _DatabaseBrowserState extends State<_DatabaseBrowser> {
  final _controller = TextEditingController();
  List<DatabaseSearchResult> _results = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () => _search(value));
  }

  Future<void> _search(String query) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.repository.search(query);
      if (!mounted || request != _request) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _open(DatabaseSearchResult result) async {
    if (result.type == 'subject') {
      await openDatabaseSubject(context, widget.repository, result.code);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DatabaseCurriculumDetailScreen(
          repository: widget.repository,
          curriculumCode: result.code,
          onSelectionChanged: widget.onCurriculumSelected,
        ),
      ),
    );
    widget.onCurriculumSelected();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Text(
        'FPT Knowledge Database',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text('Browse the bundled FLM knowledge offline.'),
      const SizedBox(height: 18),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _CountCard(
            label: 'Curricula',
            value: widget.repository.curriculumCount,
          ),
          _CountCard(label: 'Subjects', value: widget.repository.subjectCount),
          _CountCard(
            label: 'Specialization curricula',
            value: widget.repository.specializationCurriculumCount,
          ),
        ],
      ),
      const SizedBox(height: 24),
      TextField(
        controller: _controller,
        onChanged: _scheduleSearch,
        onSubmitted: _search,
        decoration: InputDecoration(
          hintText: 'Search curricula or subjects...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      if (_error != null) Text('Search failed: $_error'),
      if (_controller.text.trim().isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Try CEA201, Computer Organization, kien truc may tinh, '
            'BIT_SE_K18D_19A, software engineering, or Java.',
          ),
        )
      else if (!_loading && _results.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('No matching local database records.'),
        ),
      for (final result in _results)
        Card(
          child: ListTile(
            leading: Icon(
              result.type == 'curriculum'
                  ? Icons.account_tree_outlined
                  : Icons.menu_book_outlined,
            ),
            title: Text(result.code),
            subtitle: Text(result.name),
            trailing: Text(
              result.type == 'curriculum' ? 'Curriculum' : 'Subject',
            ),
            onTap: () => _open(result),
          ),
        ),
    ],
  );
}

class _CountCard extends StatelessWidget {
  final String label;
  final int value;

  const _CountCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(label),
        ],
      ),
    ),
  );
}

class _StudentSidebar extends StatelessWidget {
  final double width;
  final StudentSection selected;
  final ValueChanged<StudentSection> onSelected;

  const _StudentSidebar({
    required this.width,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      border: Border(
        left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: SafeArea(
      left: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: Text(
                'Workspace',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _item(
              Icons.auto_awesome_outlined,
              'Ask FPT',
              StudentSection.askFpt,
            ),
            _item(
              Icons.school_outlined,
              'My Curriculum',
              StudentSection.curriculum,
            ),
            _item(Icons.storage_outlined, 'Database', StudentSection.database),
            _item(Icons.note_alt_outlined, 'My Notes', StudentSection.notes),
          ],
        ),
      ),
    ),
  );

  Widget _item(IconData icon, String label, StudentSection section) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      type: MaterialType.transparency,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected == section,
        selectedTileColor: Colors.orange.withValues(alpha: 0.18),
        leading: Icon(icon),
        title: Text(label),
        onTap: () => onSelected(section),
      ),
    ),
  );
}
