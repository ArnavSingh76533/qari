# Mushaf Line Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render printed Mushaf lines with flush margins and natural relative word spacing.

**Architecture:** Allocate words using verified printed line ends, falling back to measured whole-word lines. Shape one RTL RichText per line and fit its complete geometry with FittedBox; actual surah endings retain their natural width. Place cursor and tap anchors inside each line's transform.

**Tech Stack:** Flutter, bundled KFGQPC Uthmanic Hafs font and offline Quran corpus, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-01-mushaf-line-engine.md`

## Global Constraints

- No forced whitespace justification, Wrap body flow, artificial word margins, or source-text changes.
- Printed Page 3 has fifteen body lines; page-end lines fit unless they are true surah endings.
- Preserve live highlighting, Tajweed shaping, Hifz, markers, review taps and cursor scrolling.
- Build `lib/main_ui_preview.dart` as `com.qari.app.uipreview` without a backend requirement.

## Review Focus

- Pages with several surah openings: each banner and actual final line stays in order.
- Narrow paper and large accessibility text: complete lines and markers remain visible.
- Incomplete line metadata: no words are lost or duplicated.
- Changed cursor or hidden words: transform and tap geometry remains stable.
- Final line of a page continuing a surah: fills both margins instead of being mistaken for a surah end.

### Task 1: Line rendering and geometry

**Files:** Modify `mobile/lib/features/recitation/presentation/widgets/mushaf_reveal_view.dart`, `mobile/lib/features/recitation/presentation/pages/live_recitation_page.dart`, `mobile/test/helpers/mushaf_paragraph_helpers.dart`, `mobile/test/mushaf_justification_test.dart`, `mobile/test/mushaf_typography_test.dart`, `mobile/test/full_page_recitation_test.dart`.

**Interfaces:** Keep the view's existing inputs; add `List<int> surahEnds` populated from bundled corpus final ayahs. Each `MushafParagraph` holds one line's source spans/ranges. Test helpers transform selection rectangles into screen coordinates.

- [x] Write printed-boundary and flush-margin regressions and observe failures in GitHub Actions before changing the renderer.
- [x] Implement printed/fallback allocation, per-line fitting, surah-ending exception and transformed anchors. Add coverage for final lines, metadata fallback and scaled review taps.
- [x] Migrate single-paragraph assertions to line/body geometry and compare rendered spaces to independently shaped Hafs advances under the same uniform scale.
- [x] Run the stable Flutter CI suites with real fonts and all 604 pages. Expected: every test passes, no analyzer errors, both margins flush on fitted lines and natural marker/space geometry.
- [x] Inspect Page 1/3/6/84 and mixed-surah screenshots at phone widths; fix any clipping/overflow while preserving the width fit.
- [x] Run a fresh read-only review, restore strict formatting, commit and push verified sources.

### Task 2: Downloadable UI preview

**Files:** Existing `.github/workflows/build-ui-preview-apk.yml`.

**Interfaces:** Consume Task 1's verified source commit; produce versioned APK and GitHub artifact link.

- [ ] Run the APK workflow's offline UI and rendering gates. Expected: green tests and successful ARM64 build.
- [ ] Verify source SHA, package/version, artifact integrity and APK checksum, then provide the new download link.

Red evidence: CI 36919074121 reports one paragraph instead of three and a
182.705dp unused left margin on the short-line fixture. Both regressions fail.

Green evidence: CI 36922531043 (f19b9263), 143/143 stable tests passed,
including all 604 pages, real Hafs spaces under uniform transforms, printed
line boundaries, true surah endings, review taps/cursor anchors and real
Page 2/604 openings at 2× text scale. Inspected fresh Page 1/3/6/84/587/604
captures: Page 3 has fifteen fitted lines and straight margins. Very short
non-final rows (Page 587) necessarily enlarge when fitting the whole line;
this follows the requested full-width policy rather than stretching spaces.

Fresh read-only review found the opening text-scale regression (fixed and
verified RED→GREEN); the narrow-paper fixture now verifies visible vertical
bounds. Final APK/device behavior is checked by the build and package gates.
