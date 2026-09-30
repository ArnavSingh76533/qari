import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';

import 'mushaf_theme.dart';

/// Authentic Mushaf page chrome: an optional elegant double-rule frame, a
/// decorative surah banner, and a centred Bismillah.
///
/// The page is ONE continuous sheet of paper — there is deliberately no card
/// or container around lines or ayahs. The only boxes drawn are the page frame
/// and the surah banner, which is what a printed Mushaf actually has.
class MushafPageFrame extends StatelessWidget {
  const MushafPageFrame({
    super.key,
    required this.theme,
    required this.child,
    this.showBorder = true,
    this.surahName,
    this.surahNameArabic,
    this.surahMeta,
    this.showBismillah = false,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 18),
  });

  final MushafTheme theme;
  final Widget child;

  /// The subtle outer frame that gives the printed-Quran feel.
  final bool showBorder;

  /// When set, a decorative surah banner is drawn above [child].
  final String? surahName;
  final String? surahNameArabic;
  final String? surahMeta;

  /// Centred Bismillah, drawn between the banner and ayah 1.
  final bool showBismillah;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final inner = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (surahName != null) ...[
            MushafSurahBanner(
              theme: theme,
              name: surahName!,
              nameArabic: surahNameArabic,
              meta: surahMeta,
            ),
            const SizedBox(height: 18),
          ],
          if (showBismillah) ...[
            MushafBismillah(theme: theme),
            const SizedBox(height: 20),
          ],
          child,
        ],
      ),
    );

    if (!showBorder) return inner;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.border, width: 1.6),
        borderRadius: BorderRadius.circular(6),
      ),
      // A second, inset hairline — the classic double-rule page frame.
      child: Container(
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.border.withValues(alpha: 0.55),
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: inner,
      ),
    );
  }
}

/// The surah title plate, modelled on the printed Madinah Mushaf: a framed
/// band with lattice-filled side panels and rosette medallions around a
/// central cartouche that carries the surah name in the Uthmanic Hafs face.
class MushafSurahBanner extends StatelessWidget {
  const MushafSurahBanner({
    super.key,
    required this.theme,
    required this.name,
    this.nameArabic,
    this.meta,
    this.height = 74,
    this.showEnglishName = true,
  });

  final MushafTheme theme;

  /// English name, shown small under the Arabic title when [nameArabic] is set.
  final String name;
  final String? nameArabic;

  /// Optional caption under the plate (e.g. "Meccan · 7 ayahs").
  final String? meta;
  final double height;
  final bool showEnglishName;

  @override
  Widget build(BuildContext context) {
    final title = nameArabic != null ? 'سُورَةُ $nameArabic' : name;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SurahPlatePainter(theme),
            child: Center(
              child: Padding(
                // Keep the title inside the cartouche, clear of the medallions.
                padding: const EdgeInsets.symmetric(horizontal: 72),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        textDirection: nameArabic != null
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: AppConstants.arabicFontFamily,
                          color: theme.text,
                          fontSize: height < 74 ? 20 : 24,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (nameArabic != null && showEnglishName)
                      Text(
                        name,
                        style: TextStyle(
                          color: theme.text.withValues(alpha: 0.6),
                          fontSize: 10.5,
                          letterSpacing: 0.6,
                          height: 1.1,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (meta != null) ...[
          const SizedBox(height: 4),
          Text(
            meta!,
            style: TextStyle(
              color: theme.text.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _SurahPlatePainter extends CustomPainter {
  _SurahPlatePainter(this.t);

  final MushafTheme t;

  @override
  void paint(Canvas canvas, Size size) {
    final gold = t.accent;
    final outer = (Offset.zero & size).deflate(1);
    final inner = outer.deflate(4);

    // Band: tinted paper inside a double rule.
    canvas.drawRect(inner, Paint()..color = gold.withValues(alpha: 0.10));

    // Diamond lattice across the band (the cartouche covers the middle).
    canvas.save();
    canvas.clipRect(inner);
    final lattice = Paint()
      ..color = gold.withValues(alpha: 0.28)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    const step = 11.0;
    for (var x = inner.left - inner.height; x < inner.right; x += step) {
      canvas.drawLine(Offset(x, inner.bottom),
          Offset(x + inner.height, inner.top), lattice);
      canvas.drawLine(Offset(x, inner.top),
          Offset(x + inner.height, inner.bottom), lattice);
    }
    canvas.restore();

    final rule = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawRect(outer, rule);
    canvas.drawRect(
        inner,
        Paint()
          ..color = gold.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);

    // Central cartouche with ogee (pointed) ends.
    final cy = size.height / 2;
    final hh = inner.height * 0.40;
    final span = math.min(size.width * 0.34, size.width / 2 - 58);
    final cartouche = _cartouche(size.width / 2, cy, span, hh);
    canvas.drawPath(cartouche, Paint()..color = t.background);
    canvas.drawPath(cartouche, rule..strokeWidth = 1.4);
    canvas.drawPath(
        _cartouche(size.width / 2, cy, span - 4, hh - 3.5),
        Paint()
          ..color = gold.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7);

    // Finial dots at the cartouche tips.
    final dot = Paint()..color = gold;
    canvas.drawCircle(Offset(size.width / 2 - span - 5, cy), 2.4, dot);
    canvas.drawCircle(Offset(size.width / 2 + span + 5, cy), 2.4, dot);

    // Rosette medallions in the side panels.
    final r = inner.height * 0.30;
    final leftX = (inner.left + size.width / 2 - span - 8) / 2;
    final rightX = size.width - leftX;
    for (final x in [leftX, rightX]) {
      _rosette(canvas, Offset(x, cy), r, gold);
    }
  }

  Path _cartouche(double cx, double cy, double span, double hh) {
    final e = hh * 1.3; // length of the pointed end
    final l = cx - span, rgt = cx + span;
    final top = cy - hh, bot = cy + hh;
    return Path()
      ..moveTo(l, cy)
      ..cubicTo(l + e * 0.25, cy - hh * 0.2, l + e * 0.35, top, l + e, top)
      ..lineTo(rgt - e, top)
      ..cubicTo(rgt - e * 0.35, top, rgt - e * 0.25, cy - hh * 0.2, rgt, cy)
      ..cubicTo(
          rgt - e * 0.25, cy + hh * 0.2, rgt - e * 0.35, bot, rgt - e, bot)
      ..lineTo(l + e, bot)
      ..cubicTo(l + e * 0.35, bot, l + e * 0.25, cy + hh * 0.2, l, cy)
      ..close();
  }

  void _rosette(Canvas canvas, Offset c, double r, Color gold) {
    canvas.drawCircle(c, r, Paint()..color = t.background);
    final stroke = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawCircle(c, r, stroke);
    // Eight-point star: two overlapping squares.
    final s = r * 0.62;
    for (final a in [0.0, math.pi / 4]) {
      final path = Path();
      for (var k = 0; k < 4; k++) {
        final ang = a + k * math.pi / 2;
        final p = c + Offset(math.cos(ang), math.sin(ang)) * s * math.sqrt2;
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, stroke..strokeWidth = 0.9);
    }
    canvas.drawCircle(c, r * 0.16, Paint()..color = gold);
  }

  @override
  bool shouldRepaint(_SurahPlatePainter old) => old.t != t;
}

/// The centred Bismillah line, set in the Uthmanic Hafs face like the rest of
/// the page.
class MushafBismillah extends StatelessWidget {
  const MushafBismillah({
    super.key,
    required this.theme,
    this.fontSize = 24,
    this.lineHeight = 1.9,
  });

  final MushafTheme theme;
  final double fontSize;
  final double lineHeight;

  static const String bismillah = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        bismillah,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: AppConstants.arabicFontFamily,
          color: theme.text,
          fontSize: fontSize,
          height: lineHeight,
        ),
      ),
    );
  }
}
