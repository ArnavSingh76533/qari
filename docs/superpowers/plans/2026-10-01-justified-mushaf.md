# Natural Hafs word-spacing regression fix

Superseded by the user-requested [Mushaf line engine](2026-10-01-mushaf-line-engine.md).

The latest requirement gives natural, tight word spacing priority over forcing
both page margins flush. Short/final lines may remain right-aligned; blank
spaces must not stretch beyond the Hafs font's natural space advance.

## Implementation

- Keep one continuous `MushafParagraph` (`RichText`) with word TextSpans and
  inline ayah markers, explicit RTL direction and `TextAlign.right`.
- Measure with the same right-aligned RTL TextPainter used for painting.
- Remove the full-width trailing placeholder that forced the last real row
  to justify, and count actual rows without subtracting a dummy row.
- Remove the font-size backoff whose only purpose was justifying single-word
  rows. Retain page-size/line-budget fitting, including Page 3's fifteen rows.
- Preserve corpus text, grapheme-safe Tajweed colours, Hifz geometry, review
  hit targets, cursor anchors, and tightly coupled inline marker baselines.

## Verification

- Red CI 36898716594 (4182c380): natural Hafs space at 20dp is 4.395dp,
  but the previous renderer expands it to 115.039dp on 320dp paper and
  205.039dp on 500dp paper. Both new regression tests fail as intended.
- Green CI 36899358850 (2113f38d): all 133 tests pass; analyzer has no errors.
- Independently shape `ا ا` with the loaded Hafs font and compare every real
  separator's selection advance against its middle space (0.05dp tolerance).
  Apply this check to all 604 pages with Tajweed enabled and phone sizes,
  while checking page fit, RTL margins, source-word presence and markers.
- Fresh Page 1/3 captures at 430dp show natural word spacing, with no expanded
  interior gaps. Page 3 still has fifteen rows; all text stays in the frame.
- Preview APK workflow includes the new spacing regressions as a build gate.
  Entry remains `main_ui_preview.dart` / `com.qari.app.uipreview` for offline UI.

## Tarteel reference

Tarteel's engineering article describes edition-specific layout data and
custom fonts that extend suitable letter components (kashida), rather than
adding whitespace, before rendering onto a Skia canvas. The stock Hafs
paragraph renderer keeps natural spacing; exact letter-based justification
requires a different font/rendering engine.

https://tarteel.ai/blog/from-page-to-screen-rethinking-quran-rendering-for-the-digital-age/
