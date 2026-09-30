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
- [x] Group final word and marker into an indivisible RTL row; remove horizontal justification.
- [x] Load verified line ends and render full-width line groups with naturally centered word runs.
- [x] Match measurement to rendering, including fixed padding, markers, banners and accessibility text scale.
- [x] Run stable mobile tests, all-page fit checks, and inspect Page 3 captures at 360/430 widths.
- [x] Commit/push the verified source.

### Task 2: Updated preview APK

**Files:** preview APK workflow.
**Interface:** new APK containing the fixed renderer and offline corpus.

- [x] Trigger preview builds for renderer changes; increment preview version code per workflow run.
- [x] Require typography/full-page tests before building.
- [ ] Verify package, signature and artifact hash; deliver the updated APK.

## Verification ledger

- Original regressions: CI 36779070336 reproduced 31/121dp gaps, detached markers and 16 Page 3 lines.
- Page 3 fix: both 360/430 widths passed in run 36780312069; 360 capture inspected.
- Review found canonical rows could overflow at a hard 13dp floor. Enlarged-text regression reproduced 501px overflow; default page 501/576 widths also failed. Width fitting now permits smaller glyphs while retaining fixed gaps.
- Decoded layout map replaces a cached asynchronous Future so later page loads resolve independently.
- Ruling: preserve corpus/ASR word order for the 25 corpus pages that span other printed pages; these retain natural flow rather than applying mismatched line positions. Changing page membership belongs to a separate corpus correction.

- Verification: CI 36780661407 passed all 110 mobile tests, including every page's frame margins and final marker/control separation. Page 3 night screenshots at 360/430 were inspected.
- The independently requested V1 page/line fields produced exactly the same 579 page arrays as the initial API metadata.
- Final important review finding resolved: enlarged-text/narrow-paper regression went RED (501px overflow) to GREEN, and the full suite passed.
- Final formatting commit copies the exact test source emitted and tested by CI and restores non-mutating formatting checks; no app code or asset changes.
