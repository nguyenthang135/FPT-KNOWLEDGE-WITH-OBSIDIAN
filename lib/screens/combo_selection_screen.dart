import 'package:flutter/material.dart';

import '../design_system/fpt_loading.dart';
import '../flm/flm_combo_service.dart';

class ComboSelectionScreen
    extends StatefulWidget {
  final String curriculumCode;

  const ComboSelectionScreen({
    super.key,
    required this.curriculumCode,
  });

  @override
  State<ComboSelectionScreen>
      createState() =>
          _ComboSelectionScreenState();
}

class _ComboSelectionScreenState
    extends State<ComboSelectionScreen> {
  final FlmComboService _service =
      FlmComboService();

  bool _loading = true;
  String? _error;

  String? _loadingComboUrl;

  List<ComboOption> _options = [];

  @override
  void initState() {
    super.initState();

    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final options =
          await _service
              .loadAvailableCombos(
        widget.curriculumCode,
      );

      if (!mounted) return;

      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _choose(
    ComboOption option,
  ) async {
    if (_loadingComboUrl != null) {
      return;
    }

    setState(() {
      _loadingComboUrl =
          option.detailUrl;
    });

    try {
      final combo =
          await _service.loadCombo(
        option,
      );

      if (!mounted) return;

      Navigator.of(context).pop(
        combo,
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error =
            'Could not load specialization.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingComboUrl = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'Choose specialization',
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const FptTechLoading(
        title: 'Combo Electives',
        subtitle: 'Fetching elective subjects and paths from FLM...',
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.all(32),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(
                height: 20,
              ),

              FilledButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _loading = true;
                  });

                  _loadOptions();
                },
                child:
                    const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_options.isEmpty) {
      return const Center(
        child: Text(
          'No specialization options were found for this curriculum.',
        ),
      );
    }

    return ListView(
      padding:
          const EdgeInsets.all(28),
      children: [
        Text(
          'Choose your career path',
          style: Theme.of(context)
              .textTheme
              .headlineMedium,
        ),

        const SizedBox(
          height: 8,
        ),

        const Text(
          'FLM will provide the subjects and semesters '
          'belonging to the specialization you choose.',
        ),

        const SizedBox(
          height: 28,
        ),

        for (final option
            in _options)
          Card(
            margin:
                const EdgeInsets.only(
              bottom: 12,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons
                        .route_outlined,
                    size: 30,
                  ),

                  const SizedBox(
                    width: 16,
                  ),

                  Expanded(
                    child: Text(
                      option.name
                              .trim()
                              .isEmpty
                          ? 'Specialization'
                          : option.name,
                      style:
                          const TextStyle(
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: 16,
                  ),

                  FilledButton(
                    onPressed:
                        _loadingComboUrl ==
                                null
                            ? () =>
                                _choose(
                                  option,
                                )
                            : null,
                    child:
                        _loadingComboUrl ==
                                option
                                    .detailUrl
                            ? const SizedBox(
                                width:
                                    18,
                                height:
                                    18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                ),
                              )
                            : const Text(
                                'Choose',
                              ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}