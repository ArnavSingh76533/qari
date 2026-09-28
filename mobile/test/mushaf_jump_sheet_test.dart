import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_jump_sheet.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';

Widget wrap(MushafTheme t, {ValueChanged<MushafJumpTarget>? onPick}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => MushafJumpSheet.show(
              ctx,
              theme: t,
              initialSurah: 1,
              initialAyahFrom: 1,
              initialAyahTo: 7,
              initialAyahCount: 7,
            ).then((v) {
              if (v != null) onPick?.call(v);
            }),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('jump sheet opens with surah + ayah range controls', (tester) async {
    await tester.pumpWidget(wrap(MushafTheme.night));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Jump to a verse'), findsOneWidget);
    expect(find.text('Surah'), findsOneWidget);
    expect(find.text('From ayah'), findsOneWidget);
    expect(find.text('To ayah'), findsOneWidget);
    expect(find.text('Jump here'), findsOneWidget);
  });

  testWidgets('confirming returns the chosen range', (tester) async {
    MushafJumpTarget? picked;
    await tester.pumpWidget(wrap(
      MushafTheme.night,
      onPick: (v) => picked = v,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jump here'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.surah, 1);
    expect(picked!.ayahFrom, 1);
    expect(picked!.ayahTo, 7);
  });

  testWidgets('dismissing returns null', (tester) async {
    MushafJumpTarget? picked;
    await tester.pumpWidget(wrap(
      MushafTheme.night,
      onPick: (v) => picked = v,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the scrim above the sheet to dismiss.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('renders on every theme preset', (tester) async {
    for (final t in MushafTheme.all) {
      await tester.pumpWidget(wrap(t));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Jump here'), findsOneWidget, reason: t.id);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    }
  });
}
