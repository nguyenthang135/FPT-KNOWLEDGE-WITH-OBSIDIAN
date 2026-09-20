import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../flm/flm_session.dart';
import '../settings/app_settings.dart';
import 'curriculum_setup_screen.dart';

class FlmLoginScreen
    extends StatefulWidget {
  const FlmLoginScreen({
    super.key,
  });

  @override
  State<FlmLoginScreen> createState() =>
      _FlmLoginScreenState();
}

class _FlmLoginScreenState
    extends State<FlmLoginScreen> {
  final FlmSession _session =
      FlmSession.instance;

  final AppSettings _settings =
      AppSettings.instance;

  StreamSubscription<LoadingState>?
      _loadingSubscription;

  bool _initializing = true;
  bool _pageLoading = true;
  bool _keepMeSignedIn = false;
  bool _navigatingAway = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final keepSignedIn =
          await _settings
              .getKeepMeSignedIn();

      if (!mounted) {
        return;
      }

      setState(() {
        _keepMeSignedIn =
            keepSignedIn;
      });

      await _session.initialize();

      // If user did NOT ask us to remember authentication,
      // remove the browser session before showing FLM.
      if (!keepSignedIn) {
        await _session.controller
            .clearCookies();

        await _session.controller
            .clearCache();
      }

      await _loadingSubscription
          ?.cancel();

      _loadingSubscription =
          _session.controller.loadingState
              .listen(
        (state) {
          if (!mounted) {
            return;
          }

          setState(() {
            _pageLoading =
                state ==
                    LoadingState.loading;
          });

          if (state ==
              LoadingState
                  .navigationCompleted) {
            _checkLogin();
          }
        },
      );

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
        _error =
            error.toString();
      });
    }
  }

  Future<void> _checkLogin() async {
    if (_navigatingAway) {
      return;
    }

    final loggedIn =
        await _session
            .checkLoginSuccess();

    if (!loggedIn ||
        !mounted ||
        _navigatingAway) {
      return;
    }

    _navigatingAway = true;

    Navigator.of(context)
        .pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            const CurriculumSetupScreen(),
      ),
    );
  }

  Future<void>
      _changeKeepSignedIn(
    bool value,
  ) async {
    setState(() {
      _keepMeSignedIn = value;
    });

    await _settings
        .setKeepMeSignedIn(
      value,
    );
  }

  @override
  void dispose() {
    _loadingSubscription
        ?.cancel();

    // DO NOT dispose FlmSession's WebView controller.
    // The authenticated controller is intentionally
    // shared by the rest of the application.

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Login to FPT FLM',
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
            child: Row(
              children: [
                Checkbox(
                  value:
                      _keepMeSignedIn,
                  onChanged:
                      _initializing
                          ? null
                          : (value) {
                              _changeKeepSignedIn(
                                value ??
                                    false,
                              );
                            },
                ),

                const SizedBox(
                  width: 6,
                ),

                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Keep me signed in on this device',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                      SizedBox(
                        height: 2,
                      ),
                      Text(
                        'Do not enable this on a shared computer.',
                        style: TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(
            height: 1,
          ),

          if (_pageLoading &&
              !_initializing)
            const LinearProgressIndicator(),

          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_initializing) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.all(
            32,
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 42,
              ),

              const SizedBox(
                height: 16,
              ),

              Text(
                'Could not start FLM login.\n\n$_error',
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(
                height: 20,
              ),

              FilledButton(
                onPressed: () {
                  setState(() {
                    _initializing =
                        true;
                    _error = null;
                  });

                  _initialize();
                },
                child: const Text(
                  'Retry',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Webview(
      _session.controller,
    );
  }
}