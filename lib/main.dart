import 'package:flutter/material.dart';
import 'vault/note_file.dart';
import 'vault/local_vault_repository.dart';
import 'vault/vault_controller.dart';
import 'vault/vault_picker.dart';
import 'vault/vault_tree.dart';

void main() {
  runApp(const FptuSeBrainApp());
}

class AppColors {
  static const background = Color(0xFF0B1220);
  static const surface = Color(0xFF152238);
  static const surfaceLight = Color(0xFF1E293B);
  static const primary = Color(0xFFF97316);
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const success = Color(0xFF4ADE80);
}

class FptuSeBrainApp extends StatelessWidget {
  const FptuSeBrainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FPTU SE Brain',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          surface: AppColors.surface,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
      home: const WorkspaceScreen(),
    );
  }
}

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _vault = VaultController(const LocalVaultRepository());
  final _picker = const VaultPicker();
  bool _picking = false;
  String _searchText = '';
  String _aiMessage = 'Chọn một tác vụ để AI hỗ trợ bạn học bài.';

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onVaultChanged);
  }

  void _onVaultChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _vault.removeListener(_onVaultChanged);
    _vault.dispose();
    super.dispose();
  }

  Future<void> _openVault() async {
    if (_picking || _vault.scanning) return;
    setState(() => _picking = true);
    try {
      final path = await _picker.pickDirectory();
      if (!mounted || path == null) return;
      await _vault.open(path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Không mở được hộp chọn thư mục. Hãy chạy bản Windows và thử lại.')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _selectNote(NoteFile note) {
    _aiMessage = 'Chọn một tác vụ để AI hỗ trợ bạn học bài.';
    _vault.select(note);
  }

  void _showAiMessage(String action) {
    final note = _vault.selectedNote;
    if (note == null) return;
    setState(() {
      _aiMessage = '$action cho bài “${note.title}” sẽ được hiển thị tại đây '
          'sau khi phần AI được tích hợp.';
    });
  }

  Widget _reader() {
    if (_vault.reading) return const Center(child: CircularProgressIndicator());
    if (_vault.readError != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Text('${_vault.readError}\nChọn lại file để thử lại hoặc quét lại Vault.')));
    }
    final note = _vault.selectedNote;
    if (note == null) return const Center(child: Text('Chọn một ghi chú để đọc.'));
    return NotePreview(note: note);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              onSearchChanged: (value) {
                setState(() {
                  _searchText = value;
                });
              },
              onOpenVault: _picking || _vault.scanning ? null : _openVault,
            ),
            const Divider(height: 1, color: AppColors.surfaceLight),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showAiPanel = constraints.maxWidth >= 1050;

                  return Row(
                    children: [
                      SizedBox(
                        width: constraints.maxWidth < 800 ? 220 : 270,
                        child: _vault.scanning
                            ? const Center(child: CircularProgressIndicator())
                            : _vault.snapshot == null
                              ? Center(child: Padding(padding: const EdgeInsets.all(16),
                                  child: Text(_vault.error ?? 'Chọn Vault để mở thư mục ghi chú.')))
                              : VaultTree(
                                  snapshot: _vault.snapshot!,
                                  selectedPath: _vault.selectedPath,
                                  onSelect: _selectNote,
                                  query: _searchText,
                                  onRefresh: () => _vault.open(_vault.snapshot!.root.path),
                                ),
                      ),
                      const VerticalDivider(
                        width: 1,
                        color: AppColors.surfaceLight,
                      ),
                      Expanded(child: _reader()),
                      if (showAiPanel && _vault.selectedNote != null) ...[
                        const VerticalDivider(
                          width: 1,
                          color: AppColors.surfaceLight,
                        ),
                        SizedBox(
                          width: 340,
                          child: AiAssistantPanel(
                            note: _vault.selectedNote!,
                            message: _aiMessage,
                            onAction: _showAiMessage,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            _StatusBar(path: _vault.snapshot?.root.path, busy: _vault.scanning || _vault.reading),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSearchChanged, required this.onOpenVault});

  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onOpenVault;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary, size: 28),
          const SizedBox(width: 10),
          const Text(
            'FPTU SE Brain',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: TextField(
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Tìm kiếm ghi chú...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onOpenVault,
            icon: const Icon(Icons.folder_open),
            label: const Text('Chọn Vault'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class NotePreview extends StatelessWidget {
  const NotePreview({super.key, required this.note});

  final NoteFile note;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.course,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              note.title,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: note.tags
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      backgroundColor: AppColors.surfaceLight,
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 28),
            SelectableText(
              note.content!.isEmpty ? '(File rỗng)' : note.content!,
              style: const TextStyle(
                fontSize: 17,
                height: 1.65,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            SelectableText('Đường dẫn: ${note.path}\n'
                'Kích thước: ${note.sizeBytes} bytes\n'
                'Sửa lần cuối: ${note.modified.toLocal()}',
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class AiAssistantPanel extends StatelessWidget {
  const AiAssistantPanel({
    super.key,
    required this.note,
    required this.message,
    required this.onAction,
  });

  final NoteFile note;
  final String message;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'Trợ lý AI',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Hỗ trợ học tập từ ghi chú đang mở.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _AiActionButton(
              icon: Icons.summarize_outlined,
              label: 'Tóm tắt bài',
              color: AppColors.primary,
              onPressed: () => onAction('Bản tóm tắt'),
            ),
            const SizedBox(height: 10),
            _AiActionButton(
              icon: Icons.quiz_outlined,
              label: 'Tạo câu hỏi',
              color: const Color(0xFF2563EB),
              onPressed: () => onAction('Câu hỏi ôn tập'),
            ),
            const SizedBox(height: 24),
            const Text(
              'KẾT QUẢ AI',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const Spacer(),
            TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Hỏi về “${note.title}”...',
                suffixIcon: const Icon(Icons.send_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiActionButton extends StatelessWidget {
  const _AiActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({this.path, required this.busy});
  final String? path;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.storage_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Vault: ${path ?? 'Chưa chọn thư mục'}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary),
          )),
          const Icon(Icons.circle, size: 10, color: AppColors.success),
          const SizedBox(width: 8),
          Text(busy ? 'Đang tải...' : 'Sẵn sàng', style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
