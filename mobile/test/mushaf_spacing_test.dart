import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

import 'helpers/mushaf_paragraph_helpers.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('KFGQPCUthmanicHafs')
          ..addFont(rootBundle.load('assets/fonts/KFGQPCUthmanicHafs-Regular.otf')))
        .load();
  });

  for (final width in [320.0, 500.0]) {
    testWidgets('short Al-Fatihah words keep natural spaces at width $width',
        (tester) async {
      const words = ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ'];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: const MushafRevealView(
              words: words,
              statuses: [],
              mushaf: MushafTheme.classic,
              fontSize: 20,
              ayahBoundaries: [2],
              ayahLabels: ['1'],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(mushafWords(), words);
      expect(mushafTextRows(tester).length, 1);
      expectNaturalMushafSpaces(tester, reason: 'Al-Fatihah words at $width');
      expect(tester.takeException(), isNull);
    });
  }
}
