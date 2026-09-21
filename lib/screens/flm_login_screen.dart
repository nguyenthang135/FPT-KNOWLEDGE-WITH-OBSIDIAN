import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../flm/flm_session.dart';
import '../settings/app_settings.dart';
import 'curriculum_setup_screen.dart';

class FlmLoginScreen extends StatefulWidget {
  const FlmLoginScreen({super.key});

  @override
  State<FlmLoginScreen> createState() => _FlmLoginScreenState();
}

class _FlmLoginScreenState extends State<FlmLoginScreen> {
  final FlmSession _session = FlmSession.instance;

  final AppSettings _settings = AppSettings.instance;

  StreamSubscription<LoadingState>? _loadingSubscription;

  bool _initializing = true;
  bool _pageLoading = true;
  bool _navigatingAway = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Authentication is retained automatically on this device.
      await _settings.setKeepMeSignedIn(true);

      await _session.initialize();

      await _loadingSubscription?.cancel();

      _loadingSubscription = _session.controller.loadingState.listen((state) {
        if (!mounted) {
          return;
        }

        setState(() {
          _pageLoading = state == LoadingState.loading;
        });

        if (state == LoadingState.navigationCompleted) {
          _checkLogin();
        }
      });

      await _session.openLoginPage();

      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;
      });

      // Important for remembered sessions:
      // FLM may already be authenticated immediately.
      await _checkLogin();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _checkLogin() async {
    if (_navigatingAway) {
      return;
    }

    final loggedIn = await _session.checkLoginSuccess();

    if (!loggedIn || !mounted || _navigatingAway) {
      return;
    }

    _navigatingAway = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CurriculumSetupScreen()),
    );
  }

  @override
  void dispose() {
    _loadingSubscription?.cancel();

    // DO NOT dispose FlmSession's WebView controller.
    // The authenticated controller is intentionally
    // shared by the rest of the application.

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x1A0F172A),
        elevation: 1,
        iconTheme: const IconThemeData(color: Color(0xFF334155)),
        titleTextStyle: const TextStyle(
          color: Color(0xFF1F2937),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        title: const Text('Login to FPT FLM'),
      ),
      body: Column(
        children: [
          if (_pageLoading && !_initializing) const LinearProgressIndicator(),

          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 42,
                color: Color(0xFFEF4444),
              ),

              const SizedBox(height: 16),

              Text(
                'Could not start FLM login.\n\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF334155)),
              ),

              const SizedBox(height: 20),

              FilledButton(
                onPressed: () {
                  setState(() {
                    _initializing = true;
                    _error = null;
                  });

                  _initialize();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Webview(_session.controller);
  }
}
