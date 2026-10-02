import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qari/data/models/lesson_model.dart';
import 'package:qari/features/lessons/presentation/pages/lesson_player_page.dart';

void main() {
  testWidgets('lesson fill-blank TextField builds under pushed route',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const lesson = LessonModel(
      lessonId: 99,
      moduleNumber: 1,
      lessonNumber: 99,
      title: 'Harakat',
      description: 'Short vowels',
      concepts: [],
      quizQuestions: [
        QuizQuestionModel(
          id: 'vowel',
          type: QuizType.fillBlank,
          question: 'The vowel mark is called ____',
          blankAnswer: 'Fatha',
          explanation: 'A short vowel.',
        )
      ],
    );
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const LessonPlayerPage(lesson: lesson),
                )),
                child: const Text('Open lesson'),
              ))),
    )));
    await tester.tap(find.text('Open lesson'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Fatha');
    expect(find.text('Fatha'), findsOneWidget);
  });
}
