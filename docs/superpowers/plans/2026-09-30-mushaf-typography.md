# Mushaf Typography Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement the tasks below.

**Goal:** Remove stretched Arabic word gaps, attach ayah markers, preserve Page 3's fifteen printed lines, and deliver an updated offline UI APK.

**Architecture:** Preserve the existing Hafs text, tajweed, cursor and verdict widgets. Group end markers with final words and use fixed 6dp word gaps. Bundle verified printed line ends independently of text; constrain font size against line widths and page height.

**Tech Stack:** Flutter/Dart, Quran.com public v4 layout metadata, GitHub Actions.

**Spec:** User's critical typography request dated 2026-09-30.

## Global Constraints

- Never distribute surplus horizontal width between words.
- Retain corpus text and ASR word indices.
- Page 3 must show 15 lines within frame margins.
- Build the separate offline UI preview entry point.

## Review Focus

- Short last lines retain 4–6dp gaps.
- Final-word/marker pairs move together on narrow widths.
- Canonical line groups fit narrow and wide phones.
- Tajweed and Hifz visibility changes retain geometry.
- Surah banners and dense pages retain complete text above controls.

### Task 1: Natural word flow and printed lines

**Files:** renderer, live page, new layout asset/repository, typography tests.
**Interface:** optional `List<int> lineEnds` (inclusive body-word indices) in MushafRevealView; repository `getLineEnds(page)`.

- [x] Write and run typography regressions in Flutter CI. Observed gaps 31/121dp, detached marker, 16 rows.
- [ ] Group final word and marker into an indivisible RTL row; remove horizontal justification.
- [ ] Load verified line ends and render full-width line groups with naturally centered word runs.
- [ ] Match measurement to rendering, including fixed padding, markers, banners and accessibility text scale.
- [ ] Run stable mobile tests, all-page fit checks, and inspect Page 3 captures at 360/430 widths.
- [ ] Commit/push the verified source.

### Task 2: Updated preview APK

**Files:** preview APK workflow.
**Interface:** new APK containing the fixed renderer and offline corpus.

- [ ] Trigger preview builds for renderer changes; increment preview version code per workflow run.
- [ ] Require typography/full-page tests before building.
- [ ] Verify package, signature and artifact hash; deliver the updated APK.
