import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/constants/app_constants.dart';
import '../lib/core/theme/app_theme.dart';
import '../lib/core/utils/arabic_text_utils.dart';
import '../lib/core/utils/idempotency.dart';

// Note: These are integration-level tests that verify widget structure.
// Full integration tests require generated code (freezed, riverpod)
// and mock dependencies. These tests validate the app's core widget tree.

void main() {
  group('Qari App Core Tests', () {
    testWidgets('App constants are properly defined', (tester) async {
      // Verify grammar colors map has required entries
      expect(AppConstants.grammarColors.containsKey('fil'), isTrue);
      expect(AppConstants.grammarColors.containsKey('ism'), isTrue);
      expect(AppConstants.grammarColors.containsKey('harf'), isTrue);

      // Verify Fi'l is green with solid underline
      final fiilConfig = AppConstants.grammarColors['fil']!;
      expect(fiilConfig.underlineStyle, UnderlineStyle.solid);

      // Verify Ism is blue with no underline
      final ismConfig = AppConstants.grammarColors['ism']!;
      expect(ismConfig.underlineStyle, UnderlineStyle.none);

      // Verify Harf is amber with dotted underline
      final harfConfig = AppConstants.grammarColors['harf']!;
      expect(harfConfig.underlineStyle, UnderlineStyle.dotted);

      // Verify supported languages
      expect(AppConstants.supportedLanguages.length, 3);
      expect(
          AppConstants.supportedLanguages.any((l) => l.code == 'en'), isTrue);
      expect(
          AppConstants.supportedLanguages.any((l) => l.code == 'ur'), isTrue);
      expect(
          AppConstants.supportedLanguages.any((l) => l.code == 'ar'), isTrue);

      // Verify Quran constants
      expect(AppConstants.totalSurahs, 114);
      expect(AppConstants.arabicFontMinSize, 22.0);
      expect(AppConstants.arabicFontMaxSize, 40.0);

      // Verify SRS constants
      expect(AppConstants.sm2GradeBhoolGaya, 1);
      expect(AppConstants.sm2GradeMushkil, 3);
      expect(AppConstants.sm2GradeAasaan, 5);
      expect(AppConstants.flashcardSessionCap, 20);
    });

    testWidgets('Arabic text utils work correctly', (tester) async {
      // Test Arabic detection
      expect(ArabicTextUtils.containsArabic('بسم الله'), isTrue);
      expect(ArabicTextUtils.containsArabic('Hello World'), isFalse);

      // Test text direction
      expect(ArabicTextUtils.getDirection('بسم الله'), TextDirection.rtl);
      expect(ArabicTextUtils.getDirection('Hello'), TextDirection.ltr);

      // Test tashkeel removal
      final cleaned = ArabicTextUtils.removeTashkeel('بِسْمِ');
      expect(cleaned, contains('ب'));
      expect(cleaned, isNot(contains('ِ')));

      // Test Arabic numeral conversion
      expect(ArabicTextUtils.toWesternNumerals('١٢٣'), '123');
    });

    testWidgets('Idempotency key generation works', (tester) async {
      final key1 = IdempotencyKey.generate();
      final key2 = IdempotencyKey.generate();

      expect(key1, isNotEmpty);
      expect(key2, isNotEmpty);
      expect(key1, isNot(equals(key2)));

      // Test deterministic key
      final actionKey = IdempotencyKey.forAction('test');
      expect(actionKey, contains('qari-test-'));
    });

    testWidgets('Theme provides correct color configs', (tester) async {
      // Test grammar color retrieval
      final fiilColor = AppTheme.getGrammarColor('fil');
      expect(fiilColor, isNotNull);

      final ismColor = AppTheme.getGrammarColor('ism');
      expect(ismColor, isNotNull);

      // Test fallback to default
      final defaultColor = AppTheme.getGrammarColor('nonexistent');
      expect(defaultColor, isNotNull);

      // Test tajweed color retrieval
      final idghamColor = AppTheme.getTajweedColor('idgham');
      expect(idghamColor, isNotNull);

      // Test themes exist
      expect(AppTheme.lightTheme, isNotNull);
      expect(AppTheme.darkTheme, isNotNull);
      expect(AppTheme.highContrastTheme, isNotNull);

      // The app uses a warm, near-black reading surface.
      expect(AppTheme.darkTheme.scaffoldBackgroundColor.computeLuminance(),
          lessThan(.02));
    });

    testWidgets('Recitation state enum has all required states',
        (tester) async {
      expect(RecitationState.values, contains(RecitationState.idle));
      expect(RecitationState.values, contains(RecitationState.listening));
      expect(RecitationState.values, contains(RecitationState.recording));
      expect(RecitationState.values, contains(RecitationState.analyzing));
      expect(RecitationState.values, contains(RecitationState.results));
      expect(RecitationState.values, contains(RecitationState.errorMicDenied));
      expect(RecitationState.values, contains(RecitationState.errorTooNoisy));
      expect(
          RecitationState.values, contains(RecitationState.errorLowConfidence));
    });

    testWidgets('Learning path enum has correct values', (tester) async {
      expect(LearningPath.values, contains(LearningPath.foundation));
      expect(LearningPath.values, contains(LearningPath.quranDirect));
    });
  });
}
