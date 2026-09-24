import 'package:flutter/material.dart';

import '../flm/curriculum_resolver.dart';
import '../flm/flm_session.dart';
import '../settings/app_settings.dart';
import 'curriculum_overview_screen.dart';
import 'flm_database_collector_screen.dart';

class CurriculumSetupScreen extends StatefulWidget {
  const CurriculumSetupScreen({super.key});

  @override
  State<CurriculumSetupScreen> createState() => _CurriculumSetupScreenState();
}

class _CurriculumSetupScreenState extends State<CurriculumSetupScreen> {
  final TextEditingController _controller = TextEditingController();

  final CurriculumResolver _resolver = CurriculumResolver();

  final AppSettings _settings = AppSettings.instance;

  bool _searching = false;
  bool _opening = false;

  String? _errorMessage;

  CurriculumMatchResult? _result;

  List<String> _history = [];

  @override
  void initState() {
    super.initState();

    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await _settings.getCurriculumHistory();

    if (!mounted) {
      return;
    }

    setState(() {
      _history = history;
    });
  }

  Future<void> _search() async {
    final input = _controller.text.trim();

    if (input.isEmpty || _searching || _opening) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _searching = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final result = await _resolver.resolve(input);

      if (!mounted) {
        return;
      }

      if (result == null) {
        setState(() {
          _errorMessage =
              'Could not find one unique curriculum '
              'matching "$input".';
        });

        return;
      }

      setState(() {
        _result = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  Future<void> _openMatchedCurriculum() async {
    final result = _result;

    if (result == null || _opening) {
      return;
    }

    setState(() {
      _opening = true;
      _errorMessage = null;
    });

    try {
      await FlmSession.instance.openCurriculumByCode(result.matchedCode);

      await _settings.addCurriculum(result.matchedCode);

      await _loadHistory();

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              CurriculumOverviewScreen(curriculumCode: result.matchedCode),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Could not open curriculum.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  Future<void> _openRecent(String curriculumCode) async {
    if (_opening || _searching) {
      return;
    }

    setState(() {
      _opening = true;
      _errorMessage = null;
    });

    try {
      // We may currently be on any FLM page,
      // so rebuild the exact search first.
      await FlmSession.instance.searchCurriculum(curriculumCode);

      await FlmSession.instance.openCurriculumByCode(curriculumCode);

      await _settings.addCurriculum(curriculumCode);

      await _loadHistory();

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              CurriculumOverviewScreen(curriculumCode: curriculumCode),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Could not open $curriculumCode.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  Future<void> _removeHistory(String curriculumCode) async {
    await _settings.removeCurriculum(curriculumCode);

    await _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose curriculum'),
        actions: [
          IconButton(
            tooltip: 'FLM Database Collector',
            icon: const Icon(Icons.storage_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FlmDatabaseCollectorScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your curriculum',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),

                const SizedBox(height: 8),

                const Text(
                  'Enter the curriculum code you use at FPT. '
                  'For example: BIT_SE_JAVA_19A.',
                ),

                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 28),

                  Text(
                    'Recent curricula',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),

                  const SizedBox(height: 10),

                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < _history.length; i++) ...[
                          ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(
                              _history[i],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: const Text(
                              'Previously opened curriculum',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Remove from history',
                                  onPressed: _opening
                                      ? null
                                      : () {
                                          _removeHistory(_history[i]);
                                        },
                                  icon: const Icon(Icons.close),
                                ),

                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: _opening
                                ? null
                                : () {
                                    _openRecent(_history[i]);
                                  },
                          ),

                          if (i != _history.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'or enter another curriculum',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: 26),
                ] else
                  const SizedBox(height: 28),

                TextField(
                  controller: _controller,
                  enabled: !_searching && !_opening,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    _search();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Curriculum code',
                    hintText: 'BIT_SE_JAVA_19A',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                ),

                const SizedBox(height: 14),

                FilledButton.icon(
                  onPressed: _searching || _opening ? null : _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    _searching ? 'Searching FLM...' : 'Find curriculum',
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 18),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_errorMessage!)),
                        ],
                      ),
                    ),
                  ),
                ],

                if (_result != null) ...[
                  const SizedBox(height: 24),

                  _CurriculumMatchCard(
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
      ),
    );
  }
}

class _CurriculumMatchCard extends StatelessWidget {
  final CurriculumMatchResult result;
  final bool opening;
  final VoidCallback onContinue;

  const _CurriculumMatchCard({
    required this.result,
    required this.opening,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 30),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    'Curriculum found',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            _InfoLine(label: 'You entered', value: result.userCode),

            _InfoLine(label: 'FLM curriculum', value: result.matchedCode),

            _InfoLine(label: 'Program', value: result.baseCode),

            if (result.intakeCode != null && result.intakeCode!.isNotEmpty)
              _InfoLine(label: 'Intake', value: result.intakeCode!),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: opening ? null : onContinue,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),

          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
