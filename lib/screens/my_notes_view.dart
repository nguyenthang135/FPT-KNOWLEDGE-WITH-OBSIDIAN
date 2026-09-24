import 'dart:io';

import 'package:flutter/material.dart';

import '../notes/json_markdown_export_service.dart';
import '../obsidian/obsidian_desktop_service.dart';
import '../widgets/obsidian_host_view.dart';

typedef MyNotesHostBuilder = Widget Function(String vaultPath, String filePath);

class MyNotesView extends StatefulWidget {
  final JsonMarkdownExportService exportService;
  final String? folderPath;
  final Future<String?> Function() onChooseFolder;
  final ObsidianDesktopService desktopService;
  final MyNotesHostBuilder? hostBuilder;
  final String? focusItemId;
  final String? openItemId;
  final VoidCallback? onItemRequestHandled;

  const MyNotesView({
    super.key,
    required this.exportService,
    required this.folderPath,
    required this.onChooseFolder,
    this.desktopService = const ObsidianDesktopService(),
    this.hostBuilder,
    this.focusItemId,
    this.openItemId,
    this.onItemRequestHandled,
  });

  @override
  State<MyNotesView> createState() => _MyNotesViewState();
}

class _MyNotesViewState extends State<MyNotesView> {
  List<MyNotesLibraryItem> _items = const [];
  MyNotesLibraryItem? _hostedItem;
  File? _hostedFile;
  MyNotesLibraryItem? _pendingItem;
  bool _loading = true;
  bool _opening = false;
  bool _obsidianMissing = false;
  String? _error;
  String? _focusedItemId;
  final GlobalKey _focusedItemKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MyNotesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderPath != widget.folderPath) {
      _hostedItem = null;
      _hostedFile = null;
      _pendingItem = null;
      _obsidianMissing = false;
      _load();
    } else if (oldWidget.focusItemId != widget.focusItemId ||
        oldWidget.openItemId != widget.openItemId) {
      _applyRequestedItem(_items);
    }
  }

  Future<void> _load() async {
    final path = widget.folderPath?.trim() ?? '';
    if (path.isEmpty) {
      if (mounted) {
        setState(() {
          _items = const [];
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final root = Directory(path);
      if (!root.existsSync()) {
        throw StateError('The selected knowledge folder no longer exists.');
      }
      final items = await widget.exportService.listMyNotes(root);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _focusedItemId = widget.focusItemId;
      });
      _applyRequestedItem(items);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _applyRequestedItem(List<MyNotesLibraryItem> items) {
    final requested = widget.openItemId ?? widget.focusItemId;
    if (requested == null) return;
    final matches = items.where((item) => item.id == requested);
    if (matches.isEmpty) {
      widget.onItemRequestHandled?.call();
      return;
    }
    final item = matches.first;
    setState(() => _focusedItemId = item.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onItemRequestHandled?.call();
      if (widget.openItemId == requested) {
        _open(item);
      } else {
        final target = _focusedItemKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 240),
            alignment: 0.25,
          );
        }
      }
    });
  }

  Future<void> _chooseFolder() async {
    try {
      await widget.onChooseFolder();
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _open(MyNotesLibraryItem item) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _pendingItem = item;
      _obsidianMissing = false;
      _error = null;
    });
    try {
      final root = Directory(widget.folderPath!);
      final file = await widget.exportService.myNotesFile(root, item);
      if (!file.existsSync()) {
        throw StateError('The exported note file is missing. Add it again.');
      }
      final installed = await widget.desktopService.isInstalled();
      if (!mounted) return;
      if (!installed) {
        setState(() => _obsidianMissing = true);
        return;
      }
      setState(() {
        _hostedItem = item;
        _hostedFile = file;
        _pendingItem = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _remove(MyNotesLibraryItem item) async {
    try {
      await widget.exportService.removeFromMyNotes(
        Directory(widget.folderPath!),
        item,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _openDownloadPage() async {
    try {
      await widget.desktopService.openDownloadPage();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _backToLibrary() {
    setState(() {
      _hostedItem = null;
      _hostedFile = null;
      _pendingItem = null;
      _obsidianMissing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hosted = _hostedItem;
    if (hosted != null) return _hostedWorkspace(hosted);
    if (_obsidianMissing) return _missingObsidian();
    return _library();
  }

  Widget _hostedWorkspace(MyNotesLibraryItem item) {
    final root = Directory(widget.folderPath!);
    final vaultPath = '${root.path}${Platform.pathSeparator}FPT Knowledge';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: _backToLibrary,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to My Notes'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${item.code} — ${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                widget.hostBuilder?.call(vaultPath, _hostedFile!.path) ??
                ObsidianHostView(
                  vaultPath: vaultPath,
                  filePath: _hostedFile!.path,
                  desktopService: widget.desktopService,
                ),
          ),
        ],
      ),
    );
  }

  Widget _missingObsidian() => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      TextButton.icon(
        onPressed: _backToLibrary,
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back to My Notes'),
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Icon(Icons.download_outlined, size: 44),
              const SizedBox(height: 14),
              Text(
                'Obsidian is required to open this note',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your My Notes library and Markdown files remain available.',
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _openDownloadPage,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Download Obsidian'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pendingItem == null
                        ? null
                        : () => _open(_pendingItem!),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _library() => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Notes',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Personal Markdown copies exported from the read-only database.',
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _chooseFolder,
            icon: const Icon(Icons.folder_open),
            label: Text(
              widget.folderPath == null ? 'Choose folder' : 'Change folder',
            ),
          ),
        ],
      ),
      if (widget.folderPath case final path?) ...[
        const SizedBox(height: 10),
        Text(
          '$path${Platform.pathSeparator}FPT Knowledge'
          '${Platform.pathSeparator}My Notes',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 22),
      if (_error != null)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('My Notes needs attention'),
            subtitle: Text(_error!),
            trailing: IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ),
        )
      else if (widget.folderPath == null)
        const Card(
          child: ListTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('Choose a knowledge folder'),
            subtitle: Text(
              'Exports will be stored under FPT Knowledge / My Notes.',
            ),
          ),
        )
      else if (_items.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.note_alt_outlined),
            title: Text('No personal notes yet'),
            subtitle: Text(
              'Open a subject or curriculum in Database and choose Add to My Notes.',
            ),
          ),
        )
      else
        for (final item in _items)
          Card(
            key: _focusedItemId == item.id ? _focusedItemKey : null,
            color: _focusedItemId == item.id
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    item.type == MyNotesItemType.subject
                        ? Icons.menu_book_outlined
                        : Icons.account_tree_outlined,
                    size: 30,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.code,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(item.title),
                        Text(
                          item.type == MyNotesItemType.subject
                              ? 'Subject'
                              : 'Curriculum',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _opening ? null : () => _open(item),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in Obsidian'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _remove(item),
                    child: const Text('Remove from My Notes'),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
}
