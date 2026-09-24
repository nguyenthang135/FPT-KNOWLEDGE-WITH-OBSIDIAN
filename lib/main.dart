import 'package:flutter/material.dart';

import 'database/bundled_database_installer.dart';
import 'database/database_repository.dart';
import 'screens/student_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FptKnowledgeApp());
}

class FptKnowledgeApp extends StatelessWidget {
  const FptKnowledgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FPT Knowledge',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.orange,
      useMaterial3: true,
    ),
    home: const DatabaseBootstrapScreen(),
  );
}

class DatabaseBootstrapScreen extends StatefulWidget {
  const DatabaseBootstrapScreen({super.key});

  @override
  State<DatabaseBootstrapScreen> createState() =>
      _DatabaseBootstrapScreenState();
}

class _DatabaseBootstrapScreenState extends State<DatabaseBootstrapScreen> {
  DatabaseRepository? _repository;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _repository = null;
      _error = null;
    });
    try {
      final directory = await BundledDatabaseInstaller().ensureInstalled();
      final repository = DatabaseRepository(directory);
      await repository.initialize();
      if (mounted) setState(() => _repository = repository);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    if (repository != null) {
      return StudentHomeScreen(repository: repository);
    }
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school_outlined, size: 58),
                const SizedBox(height: 20),
                Text(
                  'FPT Knowledge',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 18),
                if (_error == null) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Preparing FPT Knowledge database...'),
                ] else ...[
                  const Icon(Icons.error_outline, size: 38),
                  const SizedBox(height: 12),
                  const Text(
                    'FPT Knowledge database could not be prepared.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _prepare,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
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
