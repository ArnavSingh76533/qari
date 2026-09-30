import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qari/core/theme/app_theme.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_page_frame.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/pages/live_recitation_page.dart';
import 'package:qari/features/recitation/presentation/recitation_mode.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('KFGQPCUthmanicHafs')
      ..addFont(rootBundle.load('assets/fonts/KFGQPCUthmanicHafs-Regular.otf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final roboto = FontLoader('Roboto')
        ..addFont(File(
                '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)));
      await roboto.load();
    }
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 500.0]) {
    testWidgets('short lines keep natural word gaps at width $width',
        (tester) async {
      const words = ['كَفَرُوا۟', 'سَوَآءٌ', 'عَلَيْهِمْ'];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: MushafRevealView(
              words: words,
              statuses: const [],
              mushaf: MushafTheme.classic,
              fontSize: 20,
              minimumHeight: 180,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      for (var i = 1; i < words.length; i++) {
        final previous = tester.getRect(find.text(words[i - 1]));
        final current = tester.getRect(find.text(words[i]));
        expect(current.center.dy, closeTo(previous.center.dy, 0.5));
        expect(previous.left - current.right, inInclusiveRange(4.0, 6.1),
            reason: 'surplus line width must not expand Arabic word spaces');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('an ayah marker wraps with its final word', (tester) async {
    const words = ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ'];
    var width = 16.5;
    for (final word in words) {
      final painter = TextPainter(
        text: TextSpan(
          text: word,
          style: AppTheme.arabicTextStyle(fontSize: 20)
              .copyWith(fontSize: 20, height: 1.65),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      width += painter.width;
      painter.dispose();
    }
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
    final word = tester.getRect(find.text(words.last));
    final marker = tester.getRect(find.text('١'));
    expect(marker.center.dy, closeTo(word.center.dy, 0.5),
        reason: 'the end marker must not become a separate line');
    expect(word.left - marker.right, inInclusiveRange(0.0, 6.1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('printed lines fit narrow paper with enlarged text',
      (tester) async {
    final words = List.generate(9, (i) => 'ءَأَنذَرْتَهُمْ');
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 200,
          child: MushafRevealView(
            words: words,
            statuses: const [],
            mushaf: MushafTheme.classic,
            minimumHeight: 800,
            lineEnds: const [8],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rects = find
        .text(words.first)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .toList();
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(200));
    }
    expect(rects.map((r) => r.center.dy.round()).toSet().length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(360, 740), const Size(430, 932)]) {
    testWidgets('Al-Baqarah page 3 keeps fifteen natural lines at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'mushaf_theme_id': 'night'});
      final preview = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: preview,
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: LiveRecitationPage(
            surahNumber: 2,
            ayahNumber: 6,
            initialMode: RecitationMode.tilawat,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final view = find.byType(MushafRevealView);
      final frame = tester.getRect(find.byType(MushafPageFrame));
      final rows = <int>{};
      for (final element in find
          .descendant(
            of: view,
            matching: find.byType(Text),
          )
          .evaluate()) {
        final text = element.widget as Text;
        final value = text.data ?? text.textSpan?.toPlainText() ?? '';
        if (!RegExp(r'[\u0621-\u064a]').hasMatch(value)) continue;
        final rect = tester.getRect(find.byWidget(text));
        rows.add(rect.center.dy.round());
        expect(rect.left, greaterThanOrEqualTo(frame.left));
        expect(rect.right, lessThanOrEqualTo(frame.right));
      }
      expect(rows.length, 15);
      final first = tester.getRect(find.text('إِنَّ').first);
      final second = tester.getRect(find.text('ٱلَّذِينَ').first);
      expect(first.left - second.right, inInclusiveRange(4.0, 6.1));
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_QURAN_UI')) {
        final boundary =
            preview.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file =
              File('build/review/quran-page3-${size.width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
