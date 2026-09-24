import 'package:flutter/material.dart';

import '../database/flm_database_collector.dart';
import '../database/flm_database_models.dart';

class FlmDatabaseCollectorScreen extends StatefulWidget {
  const FlmDatabaseCollectorScreen({super.key});

  @override
  State<FlmDatabaseCollectorScreen> createState() =>
      _FlmDatabaseCollectorScreenState();
}

class _FlmDatabaseCollectorScreenState
    extends State<FlmDatabaseCollectorScreen> {
  final FlmDatabaseCollector _collector = FlmDatabaseCollector();

  Map<String, dynamic>? _index;
  FlmExtractionState? _savedState;
  FlmCollectionProgress? _progress;
  String? _error;
  String? _releaseMessage;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _reloadStatus();
  }

  Future<void> _reloadStatus() async {
    final index = await _collector.readIndex();
    final state = await _collector.readState();
    if (!mounted) return;
    setState(() {
      _index = index;
      _savedState = state;
    });
  }

  Future<void> _run(String mode) async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _releaseMessage = null;
    });

    void onProgress(FlmCollectionProgress progress) {
      if (mounted) {
        setState(() => _progress = progress);
      }
    }

    try {
      final result = switch (mode) {
        'resume' => await _collector.resume(onProgress: onProgress),
        'update' => await _collector.updateDatabase(onProgress: onProgress),
        _ => await _collector.extractAll(onProgress: onProgress),
      };
      if (mounted) {
        setState(() => _savedState = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
      await _reloadStatus();
    }
  }

  Future<void> _buildRelease() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _releaseMessage = null;
    });
    try {
      final result = await _collector.buildReleaseDatabase();
      if (!mounted) return;
      setState(() {
        _releaseMessage =
            'Release database built successfully — '
            'Curricula: ${result.curriculumCount}, '
            'Subjects: ${result.subjectCount}, '
            'Syllabi: ${result.syllabusCount}';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = _index ?? const <String, dynamic>{};
    final state = _progress?.state ?? _savedState;
    final progress = _progress;

    return Scaffold(
      appBar: AppBar(title: const Text('FLM Database Collector')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Database status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusLine(
                    'Curricula',
                    state?.curriculaCompleted.length ??
                        index['curriculumCount'] ??
                        0,
                  ),
                  _StatusLine(
                    'Unique subjects',
                    state?.subjectsDiscovered.length ??
                        index['subjectCount'] ??
                        0,
                  ),
                  _StatusLine(
                    'Syllabi',
                    state?.subjectsCompleted.length ??
                        index['syllabusCount'] ??
                        0,
                  ),
                  _StatusLine(
                    'Specialization curricula',
                    index['specializationCurriculumCount'] ?? 0,
                  ),
                  _StatusLine('Last update', index['lastUpdatedAt'] ?? 'Never'),
                  const SizedBox(height: 8),
                  const Text('Working database:'),
                  SelectableText(
                    _collector.store.root.path,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  const Text('Release bundle:'),
                  SelectableText(
                    _collector.defaultReleasePath,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _running ? null : () => _run('all'),
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('Extract All FLM'),
              ),
              OutlinedButton.icon(
                onPressed: _running || state == null || state.isComplete
                    ? null
                    : () => _run('resume'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume'),
              ),
              OutlinedButton.icon(
                onPressed: _running ? null : () => _run('update'),
                icon: const Icon(Icons.refresh),
                label: const Text('Update Database'),
              ),
              OutlinedButton.icon(
                onPressed: _running ? null : _buildRelease,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Build Release Database'),
              ),
              if (_running)
                FilledButton.tonalIcon(
                  onPressed: _collector.requestPause,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
            ],
          ),
          if (_running && progress != null) ...[
            const SizedBox(height: 22),
            Text(
              progress.phase,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.total > 0
                  ? progress.current / progress.total
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              progress.total > 0
                  ? '${progress.current} / ${progress.total} — ${progress.currentItem}'
                  : progress.currentItem,
            ),
          ],
          if (state != null) ...[
            const SizedBox(height: 22),
            Text(
              'Saved progress: ${state.curriculaCompleted.length} / '
              '${state.curriculaDiscovered.length} curricula, '
              '${state.subjectsCompleted.length} / '
              '${state.subjectsDiscovered.length} syllabi.',
            ),
            if (state.failedCurricula.isNotEmpty ||
                state.failedSubjects.isNotEmpty)
              Text(
                'Failures: ${state.failedCurricula.length} curricula, '
                '${state.failedSubjects.length} subjects.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
            _StatusLine('Current FLM URL', state.diagnostics.currentUrl),
            _StatusLine(
              'Login detected',
              state.diagnostics.loginDetected?.toString() ?? 'Unknown',
            ),
            _StatusLine('Stage', state.diagnostics.stage),
            _StatusLine('Rows found', state.diagnostics.rowsFound),
            _StatusLine('Codes discovered', state.diagnostics.codesDiscovered),
            _StatusLine(
              'Current curriculum',
              state.diagnostics.currentCurriculum,
            ),
            _StatusLine('Current subject', state.diagnostics.currentSubject),
            if (state.diagnostics.lastError.isNotEmpty)
              _StatusLine('Last error', state.diagnostics.lastError),
          ],
          if (_releaseMessage != null) ...[
            const SizedBox(height: 18),
            Text(
              _releaseMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String label;
  final Object value;

  const _StatusLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 190, child: Text(label)),
          Expanded(child: Text(value.toString())),
        ],
      ),
    );
  }
}
