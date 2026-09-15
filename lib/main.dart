import 'package:flutter/material.dart';

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

class NoteItem {
  const NoteItem({
    required this.title,
    required this.course,
    required this.content,
    required this.tags,
  });

  final String title;
  final String course;
  final String content;
  final List<String> tags;
}

const demoNotes = [
  NoteItem(
    title: 'Flutter cơ bản',
    course: 'PRM393',
    content:
        'Flutter giúp tạo ứng dụng cho nhiều nền tảng từ một bộ mã nguồn. '
        'Widget là thành phần tạo nên giao diện của ứng dụng.',
    tags: ['flutter', 'widget'],
  ),
  NoteItem(
    title: 'Quản lý State',
    course: 'PRM393',
    content:
        'State là dữ liệu có thể thay đổi trong quá trình ứng dụng hoạt động. '
        'Khi state thay đổi, Flutter sẽ cập nhật phần giao diện liên quan.',
    tags: ['flutter', 'state-management'],
  ),
  NoteItem(
    title: 'Navigation & Routing',
    course: 'PRM393',
    content:
        'Navigation giúp người dùng di chuyển giữa các màn hình. Routing là '
        'cách ứng dụng quản lý những đường đi đó.',
    tags: ['flutter', 'navigation'],
  ),
  NoteItem(
    title: 'Kiểm thử phần mềm',
    course: 'SWT301',
    content:
        'Kiểm thử phần mềm giúp tìm lỗi sớm và bảo đảm sản phẩm hoạt động '
        'đúng như mong đợi.',
    tags: ['testing', 'quality'],
  ),
];

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
  NoteItem _selectedNote = demoNotes.first;
  String _searchText = '';
  String _aiMessage = 'Chọn một tác vụ để AI hỗ trợ bạn học bài.';

  List<NoteItem> get _filteredNotes {
    final keyword = _searchText.trim().toLowerCase();
    if (keyword.isEmpty) {
      return demoNotes;
    }

    return demoNotes.where((note) {
      return note.title.toLowerCase().contains(keyword) ||
          note.course.toLowerCase().contains(keyword) ||
          note.tags.any((tag) => tag.toLowerCase().contains(keyword));
    }).toList();
  }

  void _selectNote(NoteItem note) {
    setState(() {
      _selectedNote = note;
      _aiMessage = 'Bạn đang đọc “${note.title}”. AI đã sẵn sàng hỗ trợ.';
    });
  }

  void _showVaultMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chức năng chọn Vault sẽ được tích hợp ở phần đọc file.'),
      ),
    );
  }

  void _showAiMessage(String action) {
    setState(() {
      _aiMessage =
          '$action cho bài “${_selectedNote.title}” sẽ được hiển thị tại đây '
          'sau khi phần AI được tích hợp.';
    });
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
              onOpenVault: _showVaultMessage,
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
                        child: VaultSidebar(
                          notes: _filteredNotes,
                          selectedNote: _selectedNote,
                          onSelect: _selectNote,
                        ),
                      ),
                      const VerticalDivider(
                        width: 1,
                        color: AppColors.surfaceLight,
                      ),
                      Expanded(child: NotePreview(note: _selectedNote)),
                      if (showAiPanel) ...[
                        const VerticalDivider(
                          width: 1,
                          color: AppColors.surfaceLight,
                        ),
                        SizedBox(
                          width: 340,
                          child: AiAssistantPanel(
                            note: _selectedNote,
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
            const _StatusBar(),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSearchChanged, required this.onOpenVault});

  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenVault;

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

class VaultSidebar extends StatelessWidget {
  const VaultSidebar({
    super.key,
    required this.notes,
    required this.selectedNote,
    required this.onSelect,
  });

  final List<NoteItem> notes;
  final NoteItem selectedNote;
  final ValueChanged<NoteItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final courses = <String>{for (final note in notes) note.course}.toList();

    return ColoredBox(
      color: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        children: [
          const _SidebarTitle(title: 'GHI CHÚ HỌC TẬP'),
          const SizedBox(height: 12),
          if (notes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Không tìm thấy ghi chú phù hợp.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final course in courses) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.school_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    course,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            for (final note in notes.where((item) => item.course == course))
              _NoteTile(
                note: note,
                isSelected: note.title == selectedNote.title,
                onTap: () => onSelect(note),
              ),
          ],
        ],
      ),
    );
  }
}

class _SidebarTitle extends StatelessWidget {
  const _SidebarTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.isSelected,
    required this.onTap,
  });

  final NoteItem note;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? AppColors.surfaceLight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    note.title,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotePreview extends StatelessWidget {
  const NotePreview({super.key, required this.note});

  final NoteItem note;

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
            Text(
              note.content,
              style: const TextStyle(
                fontSize: 17,
                height: 1.65,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Ý chính',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const _KeyPoint(text: 'Nội dung được trình bày rõ ràng, dễ đọc.'),
            const _KeyPoint(text: 'Tags giúp người dùng phân loại kiến thức.'),
            const _KeyPoint(text: 'AI sẽ hỗ trợ tóm tắt và ôn tập bài học.'),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceLight),
              ),
              child: const SelectableText(
                'void main() {\n'
                '  runApp(const FptuSeBrainApp());\n'
                '}',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  color: Color(0xFF67E8F9),
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyPoint extends StatelessWidget {
  const _KeyPoint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, color: AppColors.primary, size: 8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
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

  final NoteItem note;
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
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: const Row(
        children: [
          Icon(
            Icons.storage_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 8),
          Text(
            'Vault: Chưa chọn thư mục',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          Spacer(),
          Icon(Icons.circle, size: 10, color: AppColors.success),
          SizedBox(width: 8),
          Text('Sẵn sàng', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
