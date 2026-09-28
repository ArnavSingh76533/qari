import 'package:flutter/material.dart';

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

/// The decorative surah banner shown at the start of a surah.
class MushafSurahBanner extends StatelessWidget {
  const MushafSurahBanner({
    super.key,
    required this.theme,
    required this.name,
    this.nameArabic,
    this.meta,
  });

  final MushafTheme theme;
  final String name;
  final String? nameArabic;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.accent, width: 1.4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'سورة',
              style: TextStyle(
                color: theme.accent,
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 2),
            if (nameArabic != null) ...[
              Text(
                nameArabic!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 26,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (meta != null) ...[
              const SizedBox(height: 2),
              Text(
                meta!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.text.withValues(alpha: 0.55),
                  fontSize: 11.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The centred Bismillah line. Uses U+FDFD (BISMILLAH ligature) so it renders
/// as a single calligraphic glyph, exactly like a printed Mushaf.
class MushafBismillah extends StatelessWidget {
  const MushafBismillah({super.key, required this.theme});

  final MushafTheme theme;

  static const String bismillah = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        bismillah,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.ornament,
          fontSize: 24,
          height: 1.9,
        ),
      ),
    );
  }
}
