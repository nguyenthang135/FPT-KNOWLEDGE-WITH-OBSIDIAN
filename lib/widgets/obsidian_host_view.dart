import 'dart:async';

import 'package:flutter/material.dart';

import '../obsidian/obsidian_desktop_service.dart';

class ObsidianHostView extends StatefulWidget {
  final String vaultPath;
  final String filePath;
  final ObsidianDesktopService desktopService;

  const ObsidianHostView({
    super.key,
    required this.vaultPath,
    required this.filePath,
    this.desktopService = const ObsidianDesktopService(),
  });

  @override
  State<ObsidianHostView> createState() => _ObsidianHostViewState();
}

class _ObsidianHostViewState extends State<ObsidianHostView>
    with WidgetsBindingObserver {
  final GlobalKey _surfaceKey = GlobalKey();

  Timer? _pollTimer;
  bool _nativeCallInProgress = false;
  ObsidianHostStatus _status = const ObsidianHostStatus(
    state: ObsidianHostState.launching,
    message: 'Preparing the Obsidian host...',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startHosting());
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _updateNativeHost(),
    );
  }

  @override
  void didUpdateWidget(covariant ObsidianHostView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.vaultPath != widget.vaultPath ||
        oldWidget.filePath != widget.filePath) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startHosting());
    }
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateNativeHost());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateNativeHost();
      unawaited(widget.desktopService.focusHost());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    unawaited(widget.desktopService.hideHost());
    super.dispose();
  }

  Future<ObsidianHostBounds?> _currentBounds() async {
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) {
      return null;
    }

    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    final position = renderObject.localToGlobal(Offset.zero);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    return ObsidianHostBounds(
      x: (position.dx * pixelRatio).round(),
      y: (position.dy * pixelRatio).round(),
      width: (renderObject.size.width * pixelRatio).round(),
      height: (renderObject.size.height * pixelRatio).round(),
    );
  }

  Future<void> _startHosting() async {
    if (_nativeCallInProgress || !mounted) {
      return;
    }

    final bounds = await _currentBounds();
    if (bounds == null || !mounted) {
      return;
    }

    _nativeCallInProgress = true;

    try {
      final status = await widget.desktopService.startHosting(
        vaultPath: widget.vaultPath,
        filePath: widget.filePath,
        bounds: bounds,
      );
      _setStatus(status);
    } catch (error) {
      _setStatus(
        ObsidianHostStatus(
          state: ObsidianHostState.failed,
          message: 'Could not start the native Obsidian host: $error',
        ),
      );
    } finally {
      _nativeCallInProgress = false;
    }
  }

  Future<void> _updateNativeHost() async {
    if (_nativeCallInProgress || !mounted) {
      return;
    }

    final bounds = await _currentBounds();
    if (bounds == null || !mounted) {
      return;
    }

    _nativeCallInProgress = true;

    try {
      final status = await widget.desktopService.updateHostBounds(bounds);
      _setStatus(status);
    } catch (error) {
      _setStatus(
        ObsidianHostStatus(
          state: ObsidianHostState.failed,
          message: 'The native Obsidian host stopped responding: $error',
        ),
      );
    } finally {
      _nativeCallInProgress = false;
    }
  }

  void _setStatus(ObsidianHostStatus status) {
    if (!mounted ||
        (_status.state == status.state && _status.message == status.message)) {
      return;
    }

    setState(() {
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _surfaceKey,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: _status.state == ObsidianHostState.failed
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.desktop_access_disabled, size: 44),
                    const SizedBox(height: 14),
                    const Text(
                      'Obsidian hosting failed',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_status.message, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _startHosting,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry hosting'),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(_status.message, textAlign: TextAlign.center),
                ],
              ),
      ),
    );
  }
}
