import 'package:flutter/material.dart';
import '../design_system/app_theme.dart';
import '../design_system/app_widgets.dart';
import '../design_system/fpt_logo.dart';
import '../flm/curriculum_resolver.dart';
import '../flm/flm_session.dart';
import '../settings/app_settings.dart';
import 'curriculum_overview_screen.dart';

class CurriculumSetupScreen extends StatefulWidget {
  const CurriculumSetupScreen({super.key});
  @override
  State<CurriculumSetupScreen> createState() => _CurriculumSetupScreenState();
}

class _CurriculumSetupScreenState extends State<CurriculumSetupScreen> {
  final _controller = TextEditingController();
  final _resolver = CurriculumResolver();
  final _settings = AppSettings.instance;
  bool _searching = false, _opening = false;
  String? _errorMessage;
  List<CurriculumSearchResult> _results = [];
  String? _lastQuery;
  List<String> _history = [];

  static const List<(String, String)> _quickFilters = [
    ('BIT_SE_JAVA_18D', 'SE Java 18D'),
    ('BIT_SE', 'Ngành SE (KTPM)'),
    ('BIT_IA', 'Ngành IA (ATTT)'),
    ('18D', 'Khóa 18D'),
    ('19A', 'Khóa 19A'),
    ('', 'Tất cả khung FLM'),
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final value = await _settings.getCurriculumHistory();
    if (mounted) setState(() => _history = value);
  }

  Future<void> _search({String? customInput}) async {
    final input = (customInput ?? _controller.text).trim();
    if (customInput != null) {
      _controller.text = customInput;
    }
    if (_searching || _opening) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _errorMessage = null;
      _results = [];
      _lastQuery = input;
    });
    try {
      final results = await _resolver.search(input);
      if (!mounted) return;
      setState(() {
        _results = results;
        if (results.isEmpty) {
          _errorMessage =
              'Không tìm thấy khung chương trình phù hợp với "$input". '
              'Bạn có thể thử tìm theo mã ngành (BIT_SE, BIT_IA), theo khóa (18D, 19A), hoặc nhấn "Tất cả khung FLM".';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openRecent(String code) => _open(code, searchFirst: true);

  Future<void> _open(
    String code, {
    required bool searchFirst,
    String? preferredCombo,
  }) async {
    if (_opening || _searching) return;
    setState(() {
      _opening = true;
      _errorMessage = null;
    });
    try {
      if (searchFirst) await FlmSession.instance.searchCurriculum(code);
      await FlmSession.instance.openCurriculumByCode(code);
      await _settings.addCurriculum(code);
      await _loadHistory();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CurriculumOverviewScreen(
            curriculumCode: code,
            preferredCombo: preferredCombo,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not open $code.\n$error');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _removeHistory(String code) async {
    await _settings.removeCurriculum(code);
    await _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: const FptBrand(logoHeight: 25, showSubtitle: false),
      ),
      body: SingleChildScrollView(
        child: MaxWidthContainer(
          maxWidth: 800,
          padding: EdgeInsets.fromLTRB(
            compact ? 20 : 32,
            compact ? 28 : 52,
            compact ? 20 : 32,
            48,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeading(
                eyebrow: 'FPT University · Learning Materials',
                title: 'Set up your curriculum',
                subtitle:
                    'Tìm kiếm và kết nối khung chương trình đào tạo FPT với Obsidian knowledge workspace.',
              ),
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 36),
                Text(
                  'Recent curricula',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text('Khung chương trình bạn đã mở gần đây:'),
                const SizedBox(height: 14),
                for (final code in _history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RecentCard(
                      code: code,
                      enabled: !_opening,
                      onOpen: () => _openRecent(code),
                      onRemove: () => _removeHistory(code),
                    ),
                  ),
              ],
              const SizedBox(height: 34),
              Text(
                'Find your curriculum',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Nhập mã khung, ngành học, khóa sinh viên, hoặc chuyên ngành combo:',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_searching && !_opening,
                textInputAction: TextInputAction.search,
                style: monoStyle.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                onSubmitted: (_) => _search(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Curriculum code or keyword',
                  hintText: 'VD: BIT_SE_JAVA_18D, BIT_SE, 18D, Java...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _results = [];
                              _errorMessage = null;
                            });
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              // Quick suggestions chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _quickFilters)
                    ActionChip(
                      avatar: const Icon(Icons.bolt, size: 14, color: AppColors.primary),
                      label: Text(item.$2),
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      onPressed: _searching || _opening
                          ? null
                          : () => _search(customInput: item.$1),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: _searching ? 'Searching FLM...' : 'Search curriculum',
                icon: Icons.search,
                loading: _searching,
                expand: true,
                onPressed: _opening ? null : () => _search(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 18),
                AppCard(
                  color: AppColors.error.withValues(alpha: .08),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 24),
                if (_results.length == 1)
                  _SingleMatchCard(
                    result: _results.first,
                    opening: _opening,
                    onContinue: () => _open(
                      _results.first.matchedCode,
                      searchFirst: false,
                      preferredCombo: _results.first.detectedCombo,
                    ),
                  )
                else
                  _MultipleMatchesView(
                    query: _lastQuery ?? '',
                    results: _results,
                    opening: _opening,
                    onSelect: (item) => _open(
                      item.matchedCode,
                      searchFirst: false,
                      preferredCombo: item.detectedCombo,
                    ),
                  ),
              ],
              if (_opening) ...[
                const SizedBox(height: 20),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                  'Opening curriculum from FLM...',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentCard extends StatefulWidget {
  const _RecentCard({
    required this.code,
    required this.enabled,
    required this.onOpen,
    required this.onRemove,
  });
  final String code;
  final bool enabled;
  final VoidCallback onOpen, onRemove;
  @override
  State<_RecentCard> createState() => _RecentCardState();
}

class _RecentCardState extends State<_RecentCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: _hover ? AppColors.hover : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: widget.enabled ? widget.onOpen : null,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history, color: AppColors.blue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.code,
                      style: monoStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Previously opened curriculum',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Curriculum options',
                onSelected: (v) {
                  if (v == 'remove') widget.onRemove();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: AppColors.error),
                        SizedBox(width: 10),
                        Text('Remove from recent'),
                      ],
                    ),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SingleMatchCard extends StatelessWidget {
  const _SingleMatchCard({
    required this.result,
    required this.opening,
    required this.onContinue,
  });
  final CurriculumSearchResult result;
  final bool opening;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => AppCard(
    color: AppColors.success.withValues(alpha: .055),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.success),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Curriculum found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (result.detectedCombo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: .4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Combo ${result.detectedCombo}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (result.explanation.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.explanation,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 28,
          runSpacing: 16,
          children: [
            _Info('CURRICULUM', result.matchedCode, mono: true),
            _Info('PROGRAM', result.baseCode),
            if (result.intakeCode?.isNotEmpty ?? false)
              _Info('INTAKE', result.intakeCode!),
            if (result.detectedCombo?.isNotEmpty ?? false)
              _Info('SPECIALIZATION', result.detectedCombo!),
          ],
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          label: result.detectedCombo != null
              ? 'Continue with ${result.detectedCombo} combo'
              : 'Continue',
          icon: Icons.arrow_forward,
          loading: opening,
          expand: true,
          onPressed: onContinue,
        ),
      ],
    ),
  );
}

class _MultipleMatchesView extends StatelessWidget {
  const _MultipleMatchesView({
    required this.query,
    required this.results,
    required this.opening,
    required this.onSelect,
  });

  final String query;
  final List<CurriculumSearchResult> results;
  final bool opening;
  final ValueChanged<CurriculumSearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.list_alt_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tìm thấy ${results.length} khung chương trình:',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Chọn khung chương trình bạn muốn thiết lập Obsidian workspace:',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        for (final item in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.school, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              item.matchedCode,
                              style: monoStyle.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (item.detectedCombo != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.detectedCombo!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.explanation,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: opening ? null : () => onSelect(item),
                    child: const Text('Chọn khung này'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value, {this.mono = false});
  final String label, value;
  final bool mono;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: (mono ? monoStyle : const TextStyle()).copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

