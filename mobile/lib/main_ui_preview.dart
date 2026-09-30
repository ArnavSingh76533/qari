import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/recitation/presentation/pages/live_recitation_page.dart';
import 'features/recitation/presentation/recitation_mode.dart';

/// Separate entry point for inspecting the Quran UI without login.
/// Production builds continue to use main.dart and their normal auth flow.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: QariUiPreviewApp()));
}

class QariUiPreviewApp extends StatelessWidget {
  const QariUiPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qari UI Preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const _PreviewHome(),
    );
  }
}

class _PreviewHome extends StatelessWidget {
  const _PreviewHome();

  void _open(BuildContext context, RecitationMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => LiveRecitationPage(
          initialMode: mode,
          onStartRecitation: () {
            ScaffoldMessenger.of(pageContext).showSnackBar(
              const SnackBar(
                content: Text(
                  'UI preview only. Voice feedback will be available after setup.',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Qari UI Preview')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Your Quran, a full page at a time',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'All 604 pages are available offline. Explore page navigation, '
                    'surah selection, Tajweed colours and reading themes.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () => _open(context, RecitationMode.tilawat),
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text('Tilawat'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _open(context, RecitationMode.hifz),
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('AI Recitation'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Tilawat shows the full text. Hifz preserves the page layout '
                    'while hiding unrecited words.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
