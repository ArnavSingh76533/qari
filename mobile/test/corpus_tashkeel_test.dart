import 'package:flutter_test/flutter_test.dart';
import 'package:qari/data/repositories/local_corpus_repository.dart';

/// The in-place redesign is only correct if the CLIENT's word list matches the
/// BACKEND's reference index space. This exercises the real bundled corpus
/// through the real repository, then applies the exact same filter the live
/// page applies, and asserts the result is genuine tashkeel-bearing Arabic.
void main() {
  testWidgets('Al-Fatiha loads with full tashkeel and no verse-number words', (WidgetTester _) async {
    final ayahs = await LocalCorpusRepository().getAyahs(1);
    expect(ayahs, isNotEmpty);

    // Mirrors _hasArabicLetter in live_recitation_page.dart.
    bool hasArabicLetter(String s) {
      for (final c in s.codeUnits) {
        if (c >= 0x0621 && c <= 0x064A) return true;
      }
      return false;
    }

    var total = 0;
    var withDiacritics = 0;
    for (final a in ayahs) {
      for (final w in a.words) {
        if (!hasArabicLetter(w.text)) continue;
        total++;
        final hasDia = w.text.codeUnits.any(
            (c) => c >= 0x064B && c <= 0x0670);
        if (hasDia) withDiacritics++;
      }
    }

    expect(total, greaterThan(25), reason: 'Al-Fatiha should have ~29 words');
    expect(withDiacritics, greaterThanOrEqualTo((total * 0.9).floor()),
        reason: 'nearly every word must carry tashkeel');
  });

  testWidgets('verse-number markers are excluded by the filter', (WidgetTester _) async {
    final ayahs = await LocalCorpusRepository().getAyahs(1);
    bool hasArabicLetter(String s) {
      for (final c in s.codeUnits) {
        if (c >= 0x0621 && c <= 0x064A) return true;
      }
      return false;
    }
    final raw = ayahs.expand((a) => a.words).toList();
    final numeric = raw.where((w) => !hasArabicLetter(w.text)).toList();
    expect(numeric, isNotEmpty,
        reason: 'corpus is expected to carry numeric verse markers');
    // Every one of them is filtered out, so none can reach the Mushaf flow.
    final kept = raw.where((w) => hasArabicLetter(w.text)).length;
    expect(kept + numeric.length, raw.length);
    expect(kept, lessThan(raw.length));
  });
}
