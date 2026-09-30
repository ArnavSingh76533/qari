import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qari/data/models/recitation_model.dart';
import 'package:qari/data/services/streaming_recitation_service.dart';
import 'package:qari/features/recitation/presentation/widgets/recitation_results.dart';

Map<String, dynamic> payload() => {
  'session_id': 'verified', 'surah_number': 1, 'ayah_number': 1,
  'overall_score': .8, 'created_at': '2026-09-30T00:00:00Z',
  'pronunciation_score': 0, 'tajweed_score': 0, 'fluency_score': 0,
  'pronunciation_available': false, 'tajweed_available': false,
  'fluency_available': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assessment availability survives JSON and history round trips', () {
    final raw = payload()..['tajweed_available'] = true;
    final result = RecitationResult.fromJson(raw);
    expect(result.toJson()['tajweed_available'], true);
    expect(result.copyWith(feedback: 'Saved').toJson()['pronunciation_available'], false);
  });

  testWidgets('unassessed metrics are never presented as failed scores', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecitationResults(
      result: RecitationResult.fromJson(payload()),
      ayahWords: const [], onWordTapped: (_) {},
      onRetry: () {}, theme: ThemeData(),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Pronunciation'), findsNothing);
    expect(find.text('Tajweed'), findsNothing);
    expect(find.text('Fluency'), findsNothing);
    expect(find.text('Word accuracy'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('signed-out live recording fails before asking for microphone access', () async {
    SharedPreferences.setMockInitialValues({});
    final service = StreamingRecitationService();
    try {
      await expectLater(service.start(surahNumber: 1, ayahNumber: 1,
        memorizationMode: false), throwsA(predicate<Object>((e) => e.toString().contains('Sign in'))));
      expect(service.state, LiveConnectionState.error);
    } finally {
      await service.dispose();
    }
  });
}
