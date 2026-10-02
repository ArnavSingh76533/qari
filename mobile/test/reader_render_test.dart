import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/features/quran_reader/presentation/pages/quran_reader_page.dart';
import '../lib/data/repositories/local_corpus_repository.dart';
import '../lib/data/services/local_storage_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('QuranReaderPage renders the bundled corpus offline',
      (tester) async {
    final ayahs =
        await tester.runAsync(() => LocalCorpusRepository().getAyahs(1));
    await tester.runAsync(() async {
      await LocalStorageService.getInstance();
      await tester.pumpWidget(
        ProviderScope(
            child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('ur'), Locale('ar')],
          home: const QuranReaderPage(
            surahNumber: 1,
            surahName: 'الفاتحة',
          ),
        )),
      );
      // Let the mocked HTTP client's immediate failure finish outside the
      // widget test's fake clock, alongside the offline corpus load.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // The bundled corpus remains visible when the optional HTTP merge fails.
    await tester.pump();

    // Sticky header shows the surah's Arabic name.
    expect(find.text('الفاتحة'), findsOneWidget);
    // The opening ayah is rendered word-by-word (not as one string), so the
    // second word of Al-Fatihah must be visible without any network.
    expect(find.text(ayahs!.first.words[1].text, findRichText: true),
        findsWidgets);
    // Ayah number badge for the first ayah.
    expect(find.text('1'), findsWidgets);
  });
}
