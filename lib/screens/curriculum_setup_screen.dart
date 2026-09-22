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
  CurriculumMatchResult? _result;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final value = await _settings.getCurriculumHistory();
    if (mounted) setState(() => _history = value);
  }

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _searching || _opening) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _errorMessage = null;
      _result = null;
    });
    try {
      final value = await _resolver.resolve(input);
      if (!mounted) return;
      setState(
        () => value == null
            ? _errorMessage =
                  'Could not find one unique curriculum matching "$input".'
            : _result = value,
      );
    } catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openMatchedCurriculum() async {
    final value = _result;
    if (value == null || _opening) return;
    await _open(value.matchedCode, searchFirst: false);
  }

  Future<void> _openRecent(String code) => _open(code, searchFirst: true);
  Future<void> _open(String code, {required bool searchFirst}) async {
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
          builder: (_) => CurriculumOverviewScreen(curriculumCode: code),
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
                eyebrow: 'FPT University · Software Engineering',
                title: 'Set up your curriculum',
                subtitle:
                    'Your FPT curriculum becomes the foundation of a structured knowledge workspace, ready to connect with Obsidian.',
              ),
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 36),
                Text(
                  'Recent curricula',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text('Jump back into a curriculum you opened recently.'),
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
                'Enter the curriculum code provided by FPT Learning Materials.',
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
                decoration: const InputDecoration(
                  labelText: 'Curriculum code',
                  hintText: 'BIT_SE_JAVA_19A',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: _searching ? 'Searching FLM...' : 'Search curriculum',
                icon: Icons.search,
                loading: _searching,
                expand: true,
                onPressed: _opening ? null : _search,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 18),
                AppCard(
                  color: AppColors.error.withValues(alpha: .08),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_errorMessage!)),
                    ],
                  ),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 22),
                _MatchCard(
                  result: _result!,
                  opening: _opening,
                  onContinue: _openMatchedCurriculum,
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

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.result,
    required this.opening,
    required this.onContinue,
  });
  final CurriculumMatchResult result;
  final bool opening;
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) => AppCard(
    color: AppColors.success.withValues(alpha: .055),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.success),
            SizedBox(width: 12),
            Text(
              'Curriculum found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 28,
          runSpacing: 16,
          children: [
            _Info('CURRICULUM', result.matchedCode, mono: true),
            _Info('PROGRAM', result.baseCode),
            if (result.intakeCode?.isNotEmpty ?? false)
              _Info('INTAKE', result.intakeCode!),
          ],
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward,
          loading: opening,
          expand: true,
          onPressed: onContinue,
        ),
      ],
    ),
  );
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
