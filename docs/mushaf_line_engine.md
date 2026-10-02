# Madinah line renderer

`MushafRevealView` now renders a Column of independent RTL lines. Each line
contains a natural-width word row inside a FittedBox. The fitted transform
maps the whole row to the available width and the printed row pitch. Word
separation uses glyph side bearings plus 30% of the Hafs font's natural space
advance. This small fixed gap preserves readability; no text separators or
flexible spacers are inserted, and no available width is distributed into gaps.
Visible Arabic ink is enlarged by 15% within the fixed row pitch by reducing
the natural line leading from 1.55 to 1.55 / 1.15. Horizontal fitting retains
the printed margins and text order. Opening rows share a single horizontal
transform and use the same glyph height as ordinary pages, preserving their
centered text without enlarging short lines independently.
Tajweed spans, Hifz visibility, live verdicts, mistake taps and cursor anchors
use the same geometry before and after a state update.

The offline `assets/mushaf_layout.json.gz` sidecar stores page/line pairs for
every word and verse marker, keyed by ayah reference. It contains no Quran
text. `scripts/build_mushaf_layout.py` retrieves the metadata from the
[Quran.com API v4](https://api.quran.com/api/v4), validates all 6,236 references,
word counts and Arabic letter order against the existing corpus, and then
writes a deterministic gzip bundle. Existing corpus text and backend word
indices remain unchanged. Verse markers have their own printed line positions.

Normal pages contain 15 slots including surah openings. Pages 1 and 2 retain
their eight-slot opening layout and centered text. Surah ranges can span
multiple sheets without shrinking all their rows into one viewport. The
renderer retains a measured fallback for callers without printed metadata;
production recitation pages always supply the bundled locations.

The default recitation appearance uses charcoal paper, white verse markers,
vivid Tajweed colours and an emerald gradient microphone with a soft halo.
Dark pages have faint dark row tiles with hairline rules and no enclosing page frame.
Stored theme and Tajweed choices remain respected. The four paper presets are
still available in appearance settings.

Verification:

```sh
cd mobile
flutter test test/mushaf_line_layout_test.dart
flutter test test/full_page_recitation_test.dart
flutter test test/mushaf_in_place_test.dart test/mushaf_scroll_anchor_test.dart \
  test/mushaf_modes_test.dart test/mushaf_red_wall_widget_test.dart
```

The full-page suite checks all 604 pages against the viewport and controls.
The line suite checks 320/360/430-pixel widths, flush row boundaries, small font-derived
inter-word gaps, text/marker order, Hifz geometry, scaled cursor anchors and
multiple-sheet ranges. For screenshots using real bundled fonts:

```sh
flutter test test/full_page_recitation_test.dart --plain-name 'complete page 6 fits' \
  --dart-define=CAPTURE_QURAN_UI=true --dart-define=MUSHAF_CAPTURE_THEME=night
```

Screenshots are written to `mobile/build/review/`. Native Android builds use
the existing production entry point; `main_ui_preview.dart` is a separate
login-free entry point for inspecting the renderer and navigation locally.
