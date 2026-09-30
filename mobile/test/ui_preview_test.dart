import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qari/main_ui_preview.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('preview opens Tilawat without an account', (tester) async {
    await tester.pumpWidget(const QariUiPreviewApp());
    await tester.pumpAndSettle();
    expect(find.text('Log In'), findsNothing);
    await tester.tap(find.text('Tilawat'));
    await tester.pumpAndSettle();
    final page = tester.widget<MushafRevealView>(
      find.byType(MushafRevealView),
    );
    expect(page.words, isNotEmpty);
    expect(page.hideUnspoken, isFalse);
    expect(find.textContaining('Page 1'), findsWidgets);
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    expect(find.textContaining('UI preview only.'), findsOneWidget);
    expect(find.textContaining('Connecting'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preview AI entry keeps Hifz without a Tilawat switch',
      (tester) async {
    await tester.pumpWidget(const QariUiPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Recitation'));
    await tester.pumpAndSettle();
    final page = tester.widget<MushafRevealView>(
      find.byType(MushafRevealView),
    );
    expect(page.words, isNotEmpty);
    expect(page.hideUnspoken, isTrue);
    expect(find.text('Tilawat'), findsNothing);
    expect(find.text('Hifz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
