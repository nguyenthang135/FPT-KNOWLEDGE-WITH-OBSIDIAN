import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'screens/flm_login_screen.dart';
import 'design_system/app_theme.dart';
import 'design_system/app_widgets.dart';
import 'design_system/fpt_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeWebViewEnvironment();

  runApp(const FptKnowledgeApp());
}

Future<void> _initializeWebViewEnvironment() async {
  final appData = Platform.environment['APPDATA'] ?? Directory.current.path;

  final profileDirectory = Directory(
    '$appData'
    '${Platform.pathSeparator}'
    'FPT Knowledge'
    '${Platform.pathSeparator}'
    'webview_profile',
  );

  if (!await profileDirectory.exists()) {
    await profileDirectory.create(recursive: true);
  }

  // FPT Knowledge has its own private WebView2 profile.
  //
  // Whether authentication is actually retained is
  // controlled by the "Keep me signed in" preference
  // on the login screen.
  await WebviewController.initializeEnvironment(
    userDataPath: profileDirectory.path,
  );
}

class FptKnowledgeApp extends StatelessWidget {
  const FptKnowledgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FPT Knowledge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _CampusBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FptLogoMark(height: 58),

                      const SizedBox(height: 24),

                      Text.rich(
                        TextSpan(
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                color: Colors.white,
                                shadows: const [
                                  Shadow(
                                    color: Color(0xCC090E1A),
                                    blurRadius: 16,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                          children: const [
                            TextSpan(text: 'Build your '),
                            TextSpan(
                              text: 'FPTU',
                              style: TextStyle(color: AppColors.primary),
                            ),
                            TextSpan(text: ' second brain'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090E1A).withValues(alpha: .48),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .08),
                          ),
                        ),
                        child: const Text(
                          'Turn your Software Engineering curriculum into a structured, connected Obsidian knowledge workspace.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 16,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                color: Color(0xFF090E1A),
                                blurRadius: 10,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      PrimaryButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const FlmLoginScreen(),
                            ),
                          );
                        },
                        icon: Icons.login,
                        label: 'Continue with FPT FLM',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampusBackground extends StatelessWidget {
  const _CampusBackground();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return ColoredBox(
      color: const Color(0xFF090E1A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              'img/dai-hoc-fpt-co-nhung-nganh-nao-24.jpg',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .32, .68, 1],
                colors: [
                  const Color(0xFF090E1A).withValues(alpha: .52),
                  const Color(0xFF090E1A).withValues(alpha: .38),
                  const Color(0xFF090E1A).withValues(alpha: .25),
                  const Color(0xFF090E1A).withValues(alpha: .12),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: width >= 1000 ? .72 : .95,
                colors: [
                  const Color(0xFF090E1A).withValues(alpha: .40),
                  const Color(0xFF090E1A).withValues(alpha: .16),
                  Colors.transparent,
                ],
                stops: const [0, .48, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF090E1A).withValues(alpha: .22),
                  Colors.transparent,
                  const Color(0xFF090E1A).withValues(alpha: .18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
