// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recitation_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RecitationResult _$RecitationResultFromJson(Map<String, dynamic> json) =>
    _RecitationResult(
      sessionId: json['session_id'] as String,
      surahNumber: (json['surah_number'] as num).toInt(),
      ayahNumber: (json['ayah_number'] as num).toInt(),
      overallScore: (json['overall_score'] as num).toDouble(),
      pronunciationScore:
          (json['pronunciation_score'] as num?)?.toDouble() ?? 0.0,
      tajweedScore: (json['tajweed_score'] as num?)?.toDouble() ?? 0.0,
      fluencyScore: (json['fluency_score'] as num?)?.toDouble() ?? 0.0,
      accuracyScore: (json['accuracy_score'] as num?)?.toDouble() ?? 0.0,
      pronunciationAvailable: json['pronunciation_available'] as bool? ?? false,
      tajweedAvailable: json['tajweed_available'] as bool? ?? false,
      fluencyAvailable: json['fluency_available'] as bool? ?? false,
      wordVerdicts: (json['word_verdicts'] as List<dynamic>?)
              ?.map((e) => WordVerdict.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      referenceAudioUrl: json['reference_audio_url'] as String?,
      userAudioUrl: json['user_audio_url'] as String?,
      feedback: json['feedback'] as String?,
      feedbackUrdu: json['feedback_urdu'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );

Map<String, dynamic> _$RecitationResultToJson(_RecitationResult instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'surah_number': instance.surahNumber,
      'ayah_number': instance.ayahNumber,
      'overall_score': instance.overallScore,
      'pronunciation_score': instance.pronunciationScore,
      'tajweed_score': instance.tajweedScore,
      'fluency_score': instance.fluencyScore,
      'accuracy_score': instance.accuracyScore,
      'pronunciation_available': instance.pronunciationAvailable,
      'tajweed_available': instance.tajweedAvailable,
      'fluency_available': instance.fluencyAvailable,
      'word_verdicts': instance.wordVerdicts,
      'reference_audio_url': instance.referenceAudioUrl,
      'user_audio_url': instance.userAudioUrl,
      'feedback': instance.feedback,
      'feedback_urdu': instance.feedbackUrdu,
      'duration_seconds': instance.durationSeconds,
      'created_at': instance.createdAt.toIso8601String(),
      'confidence': instance.confidence,
    };

_WordVerdict _$WordVerdictFromJson(Map<String, dynamic> json) => _WordVerdict(
      word: json['word'] as String,
      wordIndex: (json['word_index'] as num).toInt(),
      isCorrect: json['is_correct'] as bool,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      expectedText: json['expected_text'] as String?,
      actualText: json['actual_text'] as String?,
      errorType: json['error_type'] as String?,
      errorDescription: json['error_description'] as String?,
      referenceAudioUrl: json['reference_audio_url'] as String?,
      userAudioUrl: json['user_audio_url'] as String?,
      phonemeErrors: (json['phoneme_errors'] as List<dynamic>?)
              ?.map((e) => PhonemeError.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$WordVerdictToJson(_WordVerdict instance) =>
    <String, dynamic>{
      'word': instance.word,
      'word_index': instance.wordIndex,
      'is_correct': instance.isCorrect,
      'confidence': instance.confidence,
      'expected_text': instance.expectedText,
      'actual_text': instance.actualText,
      'error_type': instance.errorType,
      'error_description': instance.errorDescription,
      'reference_audio_url': instance.referenceAudioUrl,
      'user_audio_url': instance.userAudioUrl,
      'phoneme_errors': instance.phonemeErrors,
    };

_PhonemeError _$PhonemeErrorFromJson(Map<String, dynamic> json) =>
    _PhonemeError(
      phoneme: json['phoneme'] as String,
      expectedPhoneme: json['expected_phoneme'] as String,
      actualPhoneme: json['actual_phoneme'] as String,
      position: (json['position'] as num).toInt(),
      severity: json['severity'] as String? ?? 'minor',
    );

Map<String, dynamic> _$PhonemeErrorToJson(_PhonemeError instance) =>
    <String, dynamic>{
      'phoneme': instance.phoneme,
      'expected_phoneme': instance.expectedPhoneme,
      'actual_phoneme': instance.actualPhoneme,
      'position': instance.position,
      'severity': instance.severity,
    };
