# Justified Mushaf regression fix

The user rejected independently centered rows and requested one RTL, justified
rich-text body, with inline ayah markers and flush left/right page margins.

## Implementation

- Replace Wrap/Row word containers with one `MushafParagraph` (`RichText`).
- Preserve source text as word TextSpans; use WidgetSpans for markers/openings.
- Let Flutter shape and soft-wrap the paragraph with `TextAlign.justify`.
- A trailing non-painted wrap placeholder makes the final visible row a soft
  wrap too. Measure the paragraph and exclude only that placeholder row.
- Fit font size/leading to the paper, retaining printed line-count budgets.
- Resolve visibility, Tajweed, and mistake colour in the spans; use actual
  selection geometry for cursor anchors and mistake hit targets.

## Verification

- Regression CI ac06f353: the old Wrap renderer fails the new structural test.
- The same CI proves the final-visible-row technique spans exactly 0–320dp.
- CI run 36863706203, commit 473d015d9c5e2e2d3106d8b1756140fc66232943:
  analyzer reports no errors and all 132 tests pass.
- Real glyph/marker bounds are flush on pages 1, 3, 6 and 84; Page 3 retains
  fifteen rows. All 604 pages pass clipping, page-fit and ragged-row checks.
- Migrated recitation-state, Hifz, red-wall, review-tap and scroll-anchor tests
  pass, including normal review taps reaching the page controls.
- Visually inspected fresh Page 1/3 captures at 430dp and Page 6 at 360dp:
  both text edges are flush and ayah markers stay coupled to their final words.
- Marker placeholders use the measured alphabetic baseline. Tajweed styling
  preserves grapheme clusters and corpus-internal spaces do not stretch.
- The release workflow gates a versioned ARM64 APK on layout/offline-entry
  tests. Its entry remains `main_ui_preview.dart`, with the separate Android
  package `com.qari.app.uipreview`; backend hosting is outside this change.
