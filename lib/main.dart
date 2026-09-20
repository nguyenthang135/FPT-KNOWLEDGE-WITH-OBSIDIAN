import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'screens/flm_login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeWebViewEnvironment();

  runApp(
    const FptKnowledgeApp(),
  );
}

Future<void>
    _initializeWebViewEnvironment() async {
  final appData =
      Platform.environment[
              'APPDATA'] ??
          Directory.current.path;

  final profileDirectory =
      Directory(
    '$appData'
    '${Platform.pathSeparator}'
    'FPT Knowledge'
    '${Platform.pathSeparator}'
    'webview_profile',
  );

  if (!await profileDirectory.exists()) {
    await profileDirectory.create(
      recursive: true,
    );
  }

  // FPT Knowledge has its own private WebView2 profile.
  //
  // Whether authentication is actually retained is
  // controlled by the "Keep me signed in" preference
  // on the login screen.
  await WebviewController.initializeEnvironment(
    userDataPath:
        profileDirectory.path,
  );
}

class FptKnowledgeApp
    extends StatelessWidget {
  const FptKnowledgeApp({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      title: 'FPT Knowledge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed:
            Colors.orange,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen
    extends StatelessWidget {
  const HomeScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 520,
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
                  Icons.school_outlined,
                  size: 64,
                ),

                const SizedBox(
                  height: 24,
                ),

                Text(
                  'FPT Knowledge',
                  style:
                      Theme.of(context)
                          .textTheme
                          .headlineLarge,
                ),

                const SizedBox(
                  height: 12,
                ),

                const Text(
                  'Connect to FPT Learning Materials '
                  'and organize your curriculum in Obsidian.',
                  textAlign:
                      TextAlign.center,
                ),

                const SizedBox(
                  height: 32,
                ),

                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const FlmLoginScreen(),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.login,
                  ),
                  label: const Padding(
                    padding:
                        EdgeInsets
                            .symmetric(
                      vertical: 12,
                    ),
                    child: Text(
                      'Login with FPT FLM',
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