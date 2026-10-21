import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../database/database_repository.dart';
import '../database/flm_incremental_updater.dart';
import '../flm/flm_session.dart';
import 'flm_login_screen.dart';

class FlmDatabaseUpdateScreen extends StatefulWidget {
  final DatabaseRepository repository;
  final FlmIncrementalUpdater? updater;
  const FlmDatabaseUpdateScreen({
    super.key,
    required this.repository,
    this.updater,
  });
  @override
  State<FlmDatabaseUpdateScreen> createState() =>
      _FlmDatabaseUpdateScreenState();
}

class _FlmDatabaseUpdateScreenState extends State<FlmDatabaseUpdateScreen> {
  late final FlmIncrementalUpdater _updater =
      widget.updater ?? FlmIncrementalUpdater(widget.repository);
  bool _busy = false, _deep = false, _failed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (kDebugMode && const bool.fromEnvironment('FPT_VERIFY_FLM_UPDATE')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check();
      });
    }
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _failed = false;
      _message = 'Checking FLM…';
    });
    try {
      final result = await _updater.check(
        verifyExisting: _deep,
        onProgress: (value) {
          if (mounted) setState(() => _message = value);
        },
      );
      if (mounted) setState(() => _message = result.message);
    } catch (error) {
      if (!mounted) return;
      if (error is FlmAuthenticationExpired ||
          (!FlmSession.instance.isAuthenticated && widget.updater == null)) {
        setState(() {
          _failed = true;
          _message =
              'Your FLM session expired. Please sign in again. Your offline data is safe.';
        });
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FlmLoginScreen(repository: widget.repository),
          ),
        );
      } else {
        final failedStage = _message ?? 'Checking FLM';
        setState(() {
          _failed = true;
          _message =
              'Could not finish: $failedStage Your offline database is preserved. '
              'Check your connection and try again; completed downloads will resume.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Database Update')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(28),
            children: [
              Text(
                'Installed offline database',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.repository.curriculumCount} curricula · ${widget.repository.syllabusCount} subjects · '
                '${widget.repository.specializationCurriculumCount} specialization curricula',
              ),
              const SizedBox(height: 20),
              const Text(
                'Quick check finds new curriculum IDs visible to your FLM account and installs their missing details automatically. '
                'FLM IDs alone do not reveal edits to existing content.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _deep,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _deep = value ?? false),
                title: const Text('Also verify existing content (slow)'),
                subtitle: const Text(
                  'Downloads all visible curriculum details and referenced syllabi. '
                  'May take a long time. Existing records are never removed.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _check,
                icon: const Icon(Icons.sync),
                label: const Text('Check for Updates'),
              ),
              if (_busy) ...[
                const SizedBox(height: 20),
                const LinearProgressIndicator(),
                const Text(
                  'Keep this window open. Offline data remains available.',
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 20),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _failed ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
