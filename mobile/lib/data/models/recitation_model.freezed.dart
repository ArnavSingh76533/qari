// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recitation_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RecitationResult {
  @JsonKey(name: 'session_id')
  String get sessionId;
  @JsonKey(name: 'surah_number')
  int get surahNumber;
  @JsonKey(name: 'ayah_number')
  int get ayahNumber;
  @JsonKey(name: 'overall_score')
  double get overallScore;
  @JsonKey(name: 'pronunciation_score')
  double get pronunciationScore;
  @JsonKey(name: 'tajweed_score')
  double get tajweedScore;
  @JsonKey(name: 'fluency_score')
  double get fluencyScore;
  @JsonKey(name: 'accuracy_score')
  double get accuracyScore;
  @JsonKey(name: 'pronunciation_available')
  bool get pronunciationAvailable;
  @JsonKey(name: 'tajweed_available')
  bool get tajweedAvailable;
  @JsonKey(name: 'fluency_available')
  bool get fluencyAvailable;
  @JsonKey(name: 'word_verdicts')
  List<WordVerdict> get wordVerdicts;
  @JsonKey(name: 'reference_audio_url')
  String? get referenceAudioUrl;
  @JsonKey(name: 'user_audio_url')
  String? get userAudioUrl;
  @JsonKey(name: 'feedback')
  String? get feedback;
  @JsonKey(name: 'feedback_urdu')
  String? get feedbackUrdu;
  @JsonKey(name: 'duration_seconds')
  int get durationSeconds;
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @JsonKey(name: 'confidence')
  double get confidence;

  /// Create a copy of RecitationResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $RecitationResultCopyWith<RecitationResult> get copyWith =>
      _$RecitationResultCopyWithImpl<RecitationResult>(
          this as RecitationResult, _$identity);

  /// Serializes this RecitationResult to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is RecitationResult &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.surahNumber, surahNumber) ||
                other.surahNumber == surahNumber) &&
            (identical(other.ayahNumber, ayahNumber) ||
                other.ayahNumber == ayahNumber) &&
            (identical(other.overallScore, overallScore) ||
                other.overallScore == overallScore) &&
            (identical(other.pronunciationScore, pronunciationScore) ||
                other.pronunciationScore == pronunciationScore) &&
            (identical(other.tajweedScore, tajweedScore) ||
                other.tajweedScore == tajweedScore) &&
            (identical(other.fluencyScore, fluencyScore) ||
                other.fluencyScore == fluencyScore) &&
            (identical(other.accuracyScore, accuracyScore) ||
                other.accuracyScore == accuracyScore) &&
            (identical(other.pronunciationAvailable, pronunciationAvailable) ||
                other.pronunciationAvailable == pronunciationAvailable) &&
            (identical(other.tajweedAvailable, tajweedAvailable) ||
                other.tajweedAvailable == tajweedAvailable) &&
            (identical(other.fluencyAvailable, fluencyAvailable) ||
                other.fluencyAvailable == fluencyAvailable) &&
            const DeepCollectionEquality()
                .equals(other.wordVerdicts, wordVerdicts) &&
            (identical(other.referenceAudioUrl, referenceAudioUrl) ||
                other.referenceAudioUrl == referenceAudioUrl) &&
            (identical(other.userAudioUrl, userAudioUrl) ||
                other.userAudioUrl == userAudioUrl) &&
            (identical(other.feedback, feedback) ||
                other.feedback == feedback) &&
            (identical(other.feedbackUrdu, feedbackUrdu) ||
                other.feedbackUrdu == feedbackUrdu) &&
            (identical(other.durationSeconds, durationSeconds) ||
                other.durationSeconds == durationSeconds) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        sessionId,
        surahNumber,
        ayahNumber,
        overallScore,
        pronunciationScore,
        tajweedScore,
        fluencyScore,
        accuracyScore,
        pronunciationAvailable,
        tajweedAvailable,
        fluencyAvailable,
        const DeepCollectionEquality().hash(wordVerdicts),
        referenceAudioUrl,
        userAudioUrl,
        feedback,
        feedbackUrdu,
        durationSeconds,
        createdAt,
        confidence
      ]);

  @override
  String toString() {
    return 'RecitationResult(sessionId: $sessionId, surahNumber: $surahNumber, ayahNumber: $ayahNumber, overallScore: $overallScore, pronunciationScore: $pronunciationScore, tajweedScore: $tajweedScore, fluencyScore: $fluencyScore, accuracyScore: $accuracyScore, pronunciationAvailable: $pronunciationAvailable, tajweedAvailable: $tajweedAvailable, fluencyAvailable: $fluencyAvailable, wordVerdicts: $wordVerdicts, referenceAudioUrl: $referenceAudioUrl, userAudioUrl: $userAudioUrl, feedback: $feedback, feedbackUrdu: $feedbackUrdu, durationSeconds: $durationSeconds, createdAt: $createdAt, confidence: $confidence)';
  }
}

/// @nodoc
abstract mixin class $RecitationResultCopyWith<$Res> {
  factory $RecitationResultCopyWith(
          RecitationResult value, $Res Function(RecitationResult) _then) =
      _$RecitationResultCopyWithImpl;
  @useResult
  $Res call(
      {@JsonKey(name: 'session_id') String sessionId,
      @JsonKey(name: 'surah_number') int surahNumber,
      @JsonKey(name: 'ayah_number') int ayahNumber,
      @JsonKey(name: 'overall_score') double overallScore,
      @JsonKey(name: 'pronunciation_score') double pronunciationScore,
      @JsonKey(name: 'tajweed_score') double tajweedScore,
      @JsonKey(name: 'fluency_score') double fluencyScore,
      @JsonKey(name: 'accuracy_score') double accuracyScore,
      @JsonKey(name: 'pronunciation_available') bool pronunciationAvailable,
      @JsonKey(name: 'tajweed_available') bool tajweedAvailable,
      @JsonKey(name: 'fluency_available') bool fluencyAvailable,
      @JsonKey(name: 'word_verdicts') List<WordVerdict> wordVerdicts,
      @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
      @JsonKey(name: 'user_audio_url') String? userAudioUrl,
      @JsonKey(name: 'feedback') String? feedback,
      @JsonKey(name: 'feedback_urdu') String? feedbackUrdu,
      @JsonKey(name: 'duration_seconds') int durationSeconds,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'confidence') double confidence});
}

/// @nodoc
class _$RecitationResultCopyWithImpl<$Res>
    implements $RecitationResultCopyWith<$Res> {
  _$RecitationResultCopyWithImpl(this._self, this._then);

  final RecitationResult _self;
  final $Res Function(RecitationResult) _then;

  /// Create a copy of RecitationResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? surahNumber = null,
    Object? ayahNumber = null,
    Object? overallScore = null,
    Object? pronunciationScore = null,
    Object? tajweedScore = null,
    Object? fluencyScore = null,
    Object? accuracyScore = null,
    Object? pronunciationAvailable = null,
    Object? tajweedAvailable = null,
    Object? fluencyAvailable = null,
    Object? wordVerdicts = null,
    Object? referenceAudioUrl = freezed,
    Object? userAudioUrl = freezed,
    Object? feedback = freezed,
    Object? feedbackUrdu = freezed,
    Object? durationSeconds = null,
    Object? createdAt = null,
    Object? confidence = null,
  }) {
    return _then(_self.copyWith(
      sessionId: null == sessionId
          ? _self.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      surahNumber: null == surahNumber
          ? _self.surahNumber
          : surahNumber // ignore: cast_nullable_to_non_nullable
              as int,
      ayahNumber: null == ayahNumber
          ? _self.ayahNumber
          : ayahNumber // ignore: cast_nullable_to_non_nullable
              as int,
      overallScore: null == overallScore
          ? _self.overallScore
          : overallScore // ignore: cast_nullable_to_non_nullable
              as double,
      pronunciationScore: null == pronunciationScore
          ? _self.pronunciationScore
          : pronunciationScore // ignore: cast_nullable_to_non_nullable
              as double,
      tajweedScore: null == tajweedScore
          ? _self.tajweedScore
          : tajweedScore // ignore: cast_nullable_to_non_nullable
              as double,
      fluencyScore: null == fluencyScore
          ? _self.fluencyScore
          : fluencyScore // ignore: cast_nullable_to_non_nullable
              as double,
      accuracyScore: null == accuracyScore
          ? _self.accuracyScore
          : accuracyScore // ignore: cast_nullable_to_non_nullable
              as double,
      pronunciationAvailable: null == pronunciationAvailable
          ? _self.pronunciationAvailable
          : pronunciationAvailable // ignore: cast_nullable_to_non_nullable
              as bool,
      tajweedAvailable: null == tajweedAvailable
          ? _self.tajweedAvailable
          : tajweedAvailable // ignore: cast_nullable_to_non_nullable
              as bool,
      fluencyAvailable: null == fluencyAvailable
          ? _self.fluencyAvailable
          : fluencyAvailable // ignore: cast_nullable_to_non_nullable
              as bool,
      wordVerdicts: null == wordVerdicts
          ? _self.wordVerdicts
          : wordVerdicts // ignore: cast_nullable_to_non_nullable
              as List<WordVerdict>,
      referenceAudioUrl: freezed == referenceAudioUrl
          ? _self.referenceAudioUrl
          : referenceAudioUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      userAudioUrl: freezed == userAudioUrl
          ? _self.userAudioUrl
          : userAudioUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      feedback: freezed == feedback
          ? _self.feedback
          : feedback // ignore: cast_nullable_to_non_nullable
              as String?,
      feedbackUrdu: freezed == feedbackUrdu
          ? _self.feedbackUrdu
          : feedbackUrdu // ignore: cast_nullable_to_non_nullable
              as String?,
      durationSeconds: null == durationSeconds
          ? _self.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _self.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      confidence: null == confidence
          ? _self.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// Adds pattern-matching-related methods to [RecitationResult].
extension RecitationResultPatterns on RecitationResult {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_RecitationResult value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _RecitationResult() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_RecitationResult value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _RecitationResult():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_RecitationResult value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _RecitationResult() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            @JsonKey(name: 'session_id') String sessionId,
            @JsonKey(name: 'surah_number') int surahNumber,
            @JsonKey(name: 'ayah_number') int ayahNumber,
            @JsonKey(name: 'overall_score') double overallScore,
            @JsonKey(name: 'pronunciation_score') double pronunciationScore,
            @JsonKey(name: 'tajweed_score') double tajweedScore,
            @JsonKey(name: 'fluency_score') double fluencyScore,
            @JsonKey(name: 'accuracy_score') double accuracyScore,
            @JsonKey(name: 'pronunciation_available')
            bool pronunciationAvailable,
            @JsonKey(name: 'tajweed_available') bool tajweedAvailable,
            @JsonKey(name: 'fluency_available') bool fluencyAvailable,
            @JsonKey(name: 'word_verdicts') List<WordVerdict> wordVerdicts,
            @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
            @JsonKey(name: 'user_audio_url') String? userAudioUrl,
            @JsonKey(name: 'feedback') String? feedback,
            @JsonKey(name: 'feedback_urdu') String? feedbackUrdu,
            @JsonKey(name: 'duration_seconds') int durationSeconds,
            @JsonKey(name: 'created_at') DateTime createdAt,
            @JsonKey(name: 'confidence') double confidence)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _RecitationResult() when $default != null:
        return $default(
            _that.sessionId,
            _that.surahNumber,
            _that.ayahNumber,
            _that.overallScore,
            _that.pronunciationScore,
            _that.tajweedScore,
            _that.fluencyScore,
            _that.accuracyScore,
            _that.pronunciationAvailable,
            _that.tajweedAvailable,
            _that.fluencyAvailable,
            _that.wordVerdicts,
            _that.referenceAudioUrl,
            _that.userAudioUrl,
            _that.feedback,
            _that.feedbackUrdu,
            _that.durationSeconds,
            _that.createdAt,
            _that.confidence);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            @JsonKey(name: 'session_id') String sessionId,
            @JsonKey(name: 'surah_number') int surahNumber,
            @JsonKey(name: 'ayah_number') int ayahNumber,
            @JsonKey(name: 'overall_score') double overallScore,
            @JsonKey(name: 'pronunciation_score') double pronunciationScore,
            @JsonKey(name: 'tajweed_score') double tajweedScore,
            @JsonKey(name: 'fluency_score') double fluencyScore,
            @JsonKey(name: 'accuracy_score') double accuracyScore,
            @JsonKey(name: 'pronunciation_available')
            bool pronunciationAvailable,
            @JsonKey(name: 'tajweed_available') bool tajweedAvailable,
            @JsonKey(name: 'fluency_available') bool fluencyAvailable,
            @JsonKey(name: 'word_verdicts') List<WordVerdict> wordVerdicts,
            @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
            @JsonKey(name: 'user_audio_url') String? userAudioUrl,
            @JsonKey(name: 'feedback') String? feedback,
            @JsonKey(name: 'feedback_urdu') String? feedbackUrdu,
            @JsonKey(name: 'duration_seconds') int durationSeconds,
            @JsonKey(name: 'created_at') DateTime createdAt,
            @JsonKey(name: 'confidence') double confidence)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _RecitationResult():
        return $default(
            _that.sessionId,
            _that.surahNumber,
            _that.ayahNumber,
            _that.overallScore,
            _that.pronunciationScore,
            _that.tajweedScore,
            _that.fluencyScore,
            _that.accuracyScore,
            _that.pronunciationAvailable,
            _that.tajweedAvailable,
            _that.fluencyAvailable,
            _that.wordVerdicts,
            _that.referenceAudioUrl,
            _that.userAudioUrl,
            _that.feedback,
            _that.feedbackUrdu,
            _that.durationSeconds,
            _that.createdAt,
            _that.confidence);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            @JsonKey(name: 'session_id') String sessionId,
            @JsonKey(name: 'surah_number') int surahNumber,
            @JsonKey(name: 'ayah_number') int ayahNumber,
            @JsonKey(name: 'overall_score') double overallScore,
            @JsonKey(name: 'pronunciation_score') double pronunciationScore,
            @JsonKey(name: 'tajweed_score') double tajweedScore,
            @JsonKey(name: 'fluency_score') double fluencyScore,
            @JsonKey(name: 'accuracy_score') double accuracyScore,
            @JsonKey(name: 'pronunciation_available')
            bool pronunciationAvailable,
            @JsonKey(name: 'tajweed_available') bool tajweedAvailable,
            @JsonKey(name: 'fluency_available') bool fluencyAvailable,
            @JsonKey(name: 'word_verdicts') List<WordVerdict> wordVerdicts,
            @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
            @JsonKey(name: 'user_audio_url') String? userAudioUrl,
            @JsonKey(name: 'feedback') String? feedback,
            @JsonKey(name: 'feedback_urdu') String? feedbackUrdu,
            @JsonKey(name: 'duration_seconds') int durationSeconds,
            @JsonKey(name: 'created_at') DateTime createdAt,
            @JsonKey(name: 'confidence') double confidence)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _RecitationResult() when $default != null:
        return $default(
            _that.sessionId,
            _that.surahNumber,
            _that.ayahNumber,
            _that.overallScore,
            _that.pronunciationScore,
            _that.tajweedScore,
            _that.fluencyScore,
            _that.accuracyScore,
            _that.pronunciationAvailable,
            _that.tajweedAvailable,
            _that.fluencyAvailable,
            _that.wordVerdicts,
            _that.referenceAudioUrl,
            _that.userAudioUrl,
            _that.feedback,
            _that.feedbackUrdu,
            _that.durationSeconds,
            _that.createdAt,
            _that.confidence);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _RecitationResult implements RecitationResult {
  const _RecitationResult(
      {@JsonKey(name: 'session_id') required this.sessionId,
      @JsonKey(name: 'surah_number') required this.surahNumber,
      @JsonKey(name: 'ayah_number') required this.ayahNumber,
      @JsonKey(name: 'overall_score') required this.overallScore,
      @JsonKey(name: 'pronunciation_score') this.pronunciationScore = 0.0,
      @JsonKey(name: 'tajweed_score') this.tajweedScore = 0.0,
      @JsonKey(name: 'fluency_score') this.fluencyScore = 0.0,
      @JsonKey(name: 'accuracy_score') this.accuracyScore = 0.0,
      @JsonKey(name: 'pronunciation_available')
      this.pronunciationAvailable = false,
      @JsonKey(name: 'tajweed_available') this.tajweedAvailable = false,
      @JsonKey(name: 'fluency_available') this.fluencyAvailable = false,
      @JsonKey(name: 'word_verdicts')
      final List<WordVerdict> wordVerdicts = const [],
      @JsonKey(name: 'reference_audio_url') this.referenceAudioUrl,
      @JsonKey(name: 'user_audio_url') this.userAudioUrl,
      @JsonKey(name: 'feedback') this.feedback,
      @JsonKey(name: 'feedback_urdu') this.feedbackUrdu,
      @JsonKey(name: 'duration_seconds') this.durationSeconds = 0,
      @JsonKey(name: 'created_at') required this.createdAt,
      @JsonKey(name: 'confidence') this.confidence = 1.0})
      : _wordVerdicts = wordVerdicts;
  factory _RecitationResult.fromJson(Map<String, dynamic> json) =>
      _$RecitationResultFromJson(json);

  @override
  @JsonKey(name: 'session_id')
  final String sessionId;
  @override
  @JsonKey(name: 'surah_number')
  final int surahNumber;
  @override
  @JsonKey(name: 'ayah_number')
  final int ayahNumber;
  @override
  @JsonKey(name: 'overall_score')
  final double overallScore;
  @override
  @JsonKey(name: 'pronunciation_score')
  final double pronunciationScore;
  @override
  @JsonKey(name: 'tajweed_score')
  final double tajweedScore;
  @override
  @JsonKey(name: 'fluency_score')
  final double fluencyScore;
  @override
  @JsonKey(name: 'accuracy_score')
  final double accuracyScore;
  @override
  @JsonKey(name: 'pronunciation_available')
  final bool pronunciationAvailable;
  @override
  @JsonKey(name: 'tajweed_available')
  final bool tajweedAvailable;
  @override
  @JsonKey(name: 'fluency_available')
  final bool fluencyAvailable;
  final List<WordVerdict> _wordVerdicts;
  @override
  @JsonKey(name: 'word_verdicts')
  List<WordVerdict> get wordVerdicts {
    if (_wordVerdicts is EqualUnmodifiableListView) return _wordVerdicts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_wordVerdicts);
  }

  @override
  @JsonKey(name: 'reference_audio_url')
  final String? referenceAudioUrl;
  @override
  @JsonKey(name: 'user_audio_url')
  final String? userAudioUrl;
  @override
  @JsonKey(name: 'feedback')
  final String? feedback;
  @override
  @JsonKey(name: 'feedback_urdu')
  final String? feedbackUrdu;
  @override
  @JsonKey(name: 'duration_seconds')
  final int durationSeconds;
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @override
  @JsonKey(name: 'confidence')
  final double confidence;

  /// Create a copy of RecitationResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$RecitationResultCopyWith<_RecitationResult> get copyWith =>
      __$RecitationResultCopyWithImpl<_RecitationResult>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$RecitationResultToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _RecitationResult &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.surahNumber, surahNumber) ||
                other.surahNumber == surahNumber) &&
            (identical(other.ayahNumber, ayahNumber) ||
                other.ayahNumber == ayahNumber) &&
            (identical(other.overallScore, overallScore) ||
                other.overallScore == overallScore) &&
            (identical(other.pronunciationScore, pronunciationScore) ||
                other.pronunciationScore == pronunciationScore) &&
            (identical(other.tajweedScore, tajweedScore) ||
                other.tajweedScore == tajweedScore) &&
            (identical(other.fluencyScore, fluencyScore) ||
                other.fluencyScore == fluencyScore) &&
            (identical(other.accuracyScore, accuracyScore) ||
                other.accuracyScore == accuracyScore) &&
            (identical(other.pronunciationAvailable, pronunciationAvailable) ||
                other.pronunciationAvailable == pronunciationAvailable) &&
            (identical(other.tajweedAvailable, tajweedAvailable) ||
                other.tajweedAvailable == tajweedAvailable) &&
            (identical(other.fluencyAvailable, fluencyAvailable) ||
                other.fluencyAvailable == fluencyAvailable) &&
            const DeepCollectionEquality()
                .equals(other._wordVerdicts, _wordVerdicts) &&
            (identical(other.referenceAudioUrl, referenceAudioUrl) ||
                other.referenceAudioUrl == referenceAudioUrl) &&
            (identical(other.userAudioUrl, userAudioUrl) ||
                other.userAudioUrl == userAudioUrl) &&
            (identical(other.feedback, feedback) ||
                other.feedback == feedback) &&
            (identical(other.feedbackUrdu, feedbackUrdu) ||
                other.feedbackUrdu == feedbackUrdu) &&
            (identical(other.durationSeconds, durationSeconds) ||
                other.durationSeconds == durationSeconds) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        sessionId,
        surahNumber,
        ayahNumber,
        overallScore,
        pronunciationScore,
        tajweedScore,
        fluencyScore,
        accuracyScore,
        pronunciationAvailable,
        tajweedAvailable,
        fluencyAvailable,
        const DeepCollectionEquality().hash(_wordVerdicts),
        referenceAudioUrl,
        userAudioUrl,
        feedback,
        feedbackUrdu,
        durationSeconds,
        createdAt,
        confidence
      ]);

  @override
  String toString() {
    return 'RecitationResult(sessionId: $sessionId, surahNumber: $surahNumber, ayahNumber: $ayahNumber, overallScore: $overallScore, pronunciationScore: $pronunciationScore, tajweedScore: $tajweedScore, fluencyScore: $fluencyScore, accuracyScore: $accuracyScore, pronunciationAvailable: $pronunciationAvailable, tajweedAvailable: $tajweedAvailable, fluencyAvailable: $fluencyAvailable, wordVerdicts: $wordVerdicts, referenceAudioUrl: $referenceAudioUrl, userAudioUrl: $userAudioUrl, feedback: $feedback, feedbackUrdu: $feedbackUrdu, durationSeconds: $durationSeconds, createdAt: $createdAt, confidence: $confidence)';
  }
}

/// @nodoc
abstract mixin class _$RecitationResultCopyWith<$Res>
    implements $RecitationResultCopyWith<$Res> {
  factory _$RecitationResultCopyWith(
          _RecitationResult value, $Res Function(_RecitationResult) _then) =
      __$RecitationResultCopyWithImpl;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'session_id') String sessionId,
      @JsonKey(name: 'surah_number') int surahNumber,
      @JsonKey(name: 'ayah_number') int ayahNumber,
      @JsonKey(name: 'overall_score') double overallScore,
      @JsonKey(name: 'pronunciation_score') double pronunciationScore,
      @JsonKey(name: 'tajweed_score') double tajweedScore,
      @JsonKey(name: 'fluency_score') double fluencyScore,
      @JsonKey(name: 'accuracy_score') double accuracyScore,
      @JsonKey(name: 'pronunciation_available') bool pronunciationAvailable,
      @JsonKey(name: 'tajweed_available') bool tajweedAvailable,
      @JsonKey(name: 'fluency_available') bool fluencyAvailable,
      @JsonKey(name: 'word_verdicts') List<WordVerdict> wordVerdicts,
      @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
      @JsonKey(name: 'user_audio_url') String? userAudioUrl,
      @JsonKey(name: 'feedback') String? feedback,
      @JsonKey(name: 'feedback_urdu') String? feedbackUrdu,
      @JsonKey(name: 'duration_seconds') int durationSeconds,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'confidence') double confidence});
}

/// @nodoc
class __$RecitationResultCopyWithImpl<$Res>
    implements _$RecitationResultCopyWith<$Res> {
  __$RecitationResultCopyWithImpl(this._self, this._then);

  final _RecitationResult _self;
  final $Res Function(_RecitationResult) _then;

  /// Create a copy of RecitationResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? sessionId = null,
    Object? surahNumber = null,
    Object? ayahNumber = null,
    Object? overallScore = null,
    Object? pronunciationScore = null,
    Object? tajweedScore = null,
    Object? fluencyScore = null,
    Object? accuracyScore = null,
    Object? pronunciationAvailable = null,
    Object? tajweedAvailable = null,
    Object? fluencyAvailable = null,
    Object? wordVerdicts = null,
    Object? referenceAudioUrl = freezed,
    Object? userAudioUrl = freezed,
    Object? feedback = freezed,
    Object? feedbackUrdu = freezed,
    Object? durationSeconds = null,
    Object? createdAt = null,
    Object? confidence = null,
  }) {
    return _then(_RecitationResult(
      sessionId: null == sessionId
          ? _self.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String,
      surahNumber: null == surahNumber
          ? _self.surahNumber
          : surahNumber // ignore: cast_nullable_to_non_nullable
              as int,
      ayahNumber: null == ayahNumber
          ? _self.ayahNumber
          : ayahNumber // ignore: cast_nullable_to_non_nullable
              as int,
      overallScore: null == overallScore
          ? _self.overallScore
          : overallScore // ignore: cast_nullable_to_non_nullable
              as double,
      pronunciationScore: null == pronunciationScore
          ? _self.pronunciationScore
          : pronunciationScore // ignore: cast_nullable_to_non_nullable
              as double,
      tajweedScore: null == tajweedScore
          ? _self.tajweedScore
          : tajweedScore // ignore: cast_nullable_to_non_nullable
              as double,
      fluencyScore: null == fluencyScore
          ? _self.fluencyScore
          : fluencyScore // ignore: cast_nullable_to_non_nullable
              as double,
      accuracyScore: null == accuracyScore
          ? _self.accuracyScore
          : accuracyScore // ignore: cast_nullable_to_non_nullable
              as double,
      pronunciationAvailable: null == pronunciationAvailable
          ? _self.pronunciationAvailable
          : pronunciationAvailable // ignore: cast_nullable_to_non_nullable
              as bool,
      tajweedAvailable: null == tajweedAvailable
          ? _self.tajweedAvailable
          : tajweedAvailable // ignore: cast_nullable_to_non_nullable
              as bool,
      fluencyAvailable: null == fluencyAvailable
          ? _self.fluencyAvailable
          : fluencyAvailable // ignore: cast_nullable_to_non_nullable
              as bool,
      wordVerdicts: null == wordVerdicts
          ? _self._wordVerdicts
          : wordVerdicts // ignore: cast_nullable_to_non_nullable
              as List<WordVerdict>,
      referenceAudioUrl: freezed == referenceAudioUrl
          ? _self.referenceAudioUrl
          : referenceAudioUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      userAudioUrl: freezed == userAudioUrl
          ? _self.userAudioUrl
          : userAudioUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      feedback: freezed == feedback
          ? _self.feedback
          : feedback // ignore: cast_nullable_to_non_nullable
              as String?,
      feedbackUrdu: freezed == feedbackUrdu
          ? _self.feedbackUrdu
          : feedbackUrdu // ignore: cast_nullable_to_non_nullable
              as String?,
      durationSeconds: null == durationSeconds
          ? _self.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _self.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      confidence: null == confidence
          ? _self.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
mixin _$WordVerdict {
  String get word;
  @JsonKey(name: 'word_index')
  int get wordIndex;
  @JsonKey(name: 'is_correct')
  bool get isCorrect;
  @JsonKey(name: 'confidence')
  double get confidence;
  @JsonKey(name: 'expected_text')
  String? get expectedText;
  @JsonKey(name: 'actual_text')
  String? get actualText;
  @JsonKey(name: 'error_type')
  String? get errorType;
  @JsonKey(name: 'error_description')
  String? get errorDescription;
  @JsonKey(name: 'reference_audio_url')
  String? get referenceAudioUrl;
  @JsonKey(name: 'user_audio_url')
  String? get userAudioUrl;
  @JsonKey(name: 'phoneme_errors')
  List<PhonemeError> get phonemeErrors;

  /// Create a copy of WordVerdict
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $WordVerdictCopyWith<WordVerdict> get copyWith =>
      _$WordVerdictCopyWithImpl<WordVerdict>(this as WordVerdict, _$identity);

  /// Serializes this WordVerdict to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is WordVerdict &&
            (identical(other.word, word) || other.word == word) &&
            (identical(other.wordIndex, wordIndex) ||
                other.wordIndex == wordIndex) &&
            (identical(other.isCorrect, isCorrect) ||
                other.isCorrect == isCorrect) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            (identical(other.expectedText, expectedText) ||
                other.expectedText == expectedText) &&
            (identical(other.actualText, actualText) ||
                other.actualText == actualText) &&
            (identical(other.errorType, errorType) ||
                other.errorType == errorType) &&
            (identical(other.errorDescription, errorDescription) ||
                other.errorDescription == errorDescription) &&
            (identical(other.referenceAudioUrl, referenceAudioUrl) ||
                other.referenceAudioUrl == referenceAudioUrl) &&
            (identical(other.userAudioUrl, userAudioUrl) ||
                other.userAudioUrl == userAudioUrl) &&
            const DeepCollectionEquality()
                .equals(other.phonemeErrors, phonemeErrors));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      word,
      wordIndex,
      isCorrect,
      confidence,
      expectedText,
      actualText,
      errorType,
      errorDescription,
      referenceAudioUrl,
      userAudioUrl,
      const DeepCollectionEquality().hash(phonemeErrors));

  @override
  String toString() {
    return 'WordVerdict(word: $word, wordIndex: $wordIndex, isCorrect: $isCorrect, confidence: $confidence, expectedText: $expectedText, actualText: $actualText, errorType: $errorType, errorDescription: $errorDescription, referenceAudioUrl: $referenceAudioUrl, userAudioUrl: $userAudioUrl, phonemeErrors: $phonemeErrors)';
  }
}

/// @nodoc
abstract mixin class $WordVerdictCopyWith<$Res> {
  factory $WordVerdictCopyWith(
          WordVerdict value, $Res Function(WordVerdict) _then) =
      _$WordVerdictCopyWithImpl;
  @useResult
  $Res call(
      {String word,
      @JsonKey(name: 'word_index') int wordIndex,
      @JsonKey(name: 'is_correct') bool isCorrect,
      @JsonKey(name: 'confidence') double confidence,
      @JsonKey(name: 'expected_text') String? expectedText,
      @JsonKey(name: 'actual_text') String? actualText,
      @JsonKey(name: 'error_type') String? errorType,
      @JsonKey(name: 'error_description') String? errorDescription,
      @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
      @JsonKey(name: 'user_audio_url') String? userAudioUrl,
      @JsonKey(name: 'phoneme_errors') List<PhonemeError> phonemeErrors});
}

/// @nodoc
class _$WordVerdictCopyWithImpl<$Res> implements $WordVerdictCopyWith<$Res> {
  _$WordVerdictCopyWithImpl(this._self, this._then);

  final WordVerdict _self;
  final $Res Function(WordVerdict) _then;

  /// Create a copy of WordVerdict
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? word = null,
    Object? wordIndex = null,
    Object? isCorrect = null,
    Object? confidence = null,
    Object? expectedText = freezed,
    Object? actualText = freezed,
    Object? errorType = freezed,
    Object? errorDescription = freezed,
    Object? referenceAudioUrl = freezed,
    Object? userAudioUrl = freezed,
    Object? phonemeErrors = null,
  }) {
    return _then(_self.copyWith(
      word: null == word
          ? _self.word
          : word // ignore: cast_nullable_to_non_nullable
              as String,
      wordIndex: null == wordIndex
          ? _self.wordIndex
          : wordIndex // ignore: cast_nullable_to_non_nullable
              as int,
      isCorrect: null == isCorrect
          ? _self.isCorrect
          : isCorrect // ignore: cast_nullable_to_non_nullable
              as bool,
      confidence: null == confidence
          ? _self.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double,
      expectedText: freezed == expectedText
          ? _self.expectedText
          : expectedText // ignore: cast_nullable_to_non_nullable
              as String?,
      actualText: freezed == actualText
          ? _self.actualText
          : actualText // ignore: cast_nullable_to_non_nullable
              as String?,
      errorType: freezed == errorType
          ? _self.errorType
          : errorType // ignore: cast_nullable_to_non_nullable
              as String?,
      errorDescription: freezed == errorDescription
          ? _self.errorDescription
          : errorDescription // ignore: cast_nullable_to_non_nullable
              as String?,
      referenceAudioUrl: freezed == referenceAudioUrl
          ? _self.referenceAudioUrl
          : referenceAudioUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      userAudioUrl: freezed == userAudioUrl
          ? _self.userAudioUrl
          : userAudioUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      phonemeErrors: null == phonemeErrors
          ? _self.phonemeErrors
          : phonemeErrors // ignore: cast_nullable_to_non_nullable
              as List<PhonemeError>,
    ));
  }
}

/// Adds pattern-matching-related methods to [WordVerdict].
extension WordVerdictPatterns on WordVerdict {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_WordVerdict value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _WordVerdict() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_WordVerdict value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _WordVerdict():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_WordVerdict value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _WordVerdict() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            String word,
            @JsonKey(name: 'word_index') int wordIndex,
            @JsonKey(name: 'is_correct') bool isCorrect,
            @JsonKey(name: 'confidence') double confidence,
            @JsonKey(name: 'expected_text') String? expectedText,
            @JsonKey(name: 'actual_text') String? actualText,
            @JsonKey(name: 'error_type') String? errorType,
            @JsonKey(name: 'error_description') String? errorDescription,
            @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
            @JsonKey(name: 'user_audio_url') String? userAudioUrl,
            @JsonKey(name: 'phoneme_errors') List<PhonemeError> phonemeErrors)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _WordVerdict() when $default != null:
        return $default(
            _that.word,
            _that.wordIndex,
            _that.isCorrect,
            _that.confidence,
            _that.expectedText,
            _that.actualText,
            _that.errorType,
            _that.errorDescription,
            _that.referenceAudioUrl,
            _that.userAudioUrl,
            _that.phonemeErrors);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            String word,
            @JsonKey(name: 'word_index') int wordIndex,
            @JsonKey(name: 'is_correct') bool isCorrect,
            @JsonKey(name: 'confidence') double confidence,
            @JsonKey(name: 'expected_text') String? expectedText,
            @JsonKey(name: 'actual_text') String? actualText,
            @JsonKey(name: 'error_type') String? errorType,
            @JsonKey(name: 'error_description') String? errorDescription,
            @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
            @JsonKey(name: 'user_audio_url') String? userAudioUrl,
            @JsonKey(name: 'phoneme_errors') List<PhonemeError> phonemeErrors)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _WordVerdict():
        return $default(
            _that.word,
            _that.wordIndex,
            _that.isCorrect,
            _that.confidence,
            _that.expectedText,
            _that.actualText,
            _that.errorType,
            _that.errorDescription,
            _that.referenceAudioUrl,
            _that.userAudioUrl,
            _that.phonemeErrors);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            String word,
            @JsonKey(name: 'word_index') int wordIndex,
            @JsonKey(name: 'is_correct') bool isCorrect,
            @JsonKey(name: 'confidence') double confidence,
            @JsonKey(name: 'expected_text') String? expectedText,
            @JsonKey(name: 'actual_text') String? actualText,
            @JsonKey(name: 'error_type') String? errorType,
            @JsonKey(name: 'error_description') String? errorDescription,
            @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
            @JsonKey(name: 'user_audio_url') String? userAudioUrl,
            @JsonKey(name: 'phoneme_errors') List<PhonemeError> phonemeErrors)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _WordVerdict() when $default != null:
        return $default(
            _that.word,
            _that.wordIndex,
            _that.isCorrect,
            _that.confidence,
            _that.expectedText,
            _that.actualText,
            _that.errorType,
            _that.errorDescription,
            _that.referenceAudioUrl,
            _that.userAudioUrl,
            _that.phonemeErrors);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _WordVerdict implements WordVerdict {
  const _WordVerdict(
      {required this.word,
      @JsonKey(name: 'word_index') required this.wordIndex,
      @JsonKey(name: 'is_correct') required this.isCorrect,
      @JsonKey(name: 'confidence') this.confidence = 1.0,
      @JsonKey(name: 'expected_text') this.expectedText,
      @JsonKey(name: 'actual_text') this.actualText,
      @JsonKey(name: 'error_type') this.errorType,
      @JsonKey(name: 'error_description') this.errorDescription,
      @JsonKey(name: 'reference_audio_url') this.referenceAudioUrl,
      @JsonKey(name: 'user_audio_url') this.userAudioUrl,
      @JsonKey(name: 'phoneme_errors')
      final List<PhonemeError> phonemeErrors = const []})
      : _phonemeErrors = phonemeErrors;
  factory _WordVerdict.fromJson(Map<String, dynamic> json) =>
      _$WordVerdictFromJson(json);

  @override
  final String word;
  @override
  @JsonKey(name: 'word_index')
  final int wordIndex;
  @override
  @JsonKey(name: 'is_correct')
  final bool isCorrect;
  @override
  @JsonKey(name: 'confidence')
  final double confidence;
  @override
  @JsonKey(name: 'expected_text')
  final String? expectedText;
  @override
  @JsonKey(name: 'actual_text')
  final String? actualText;
  @override
  @JsonKey(name: 'error_type')
  final String? errorType;
  @override
  @JsonKey(name: 'error_description')
  final String? errorDescription;
  @override
  @JsonKey(name: 'reference_audio_url')
  final String? referenceAudioUrl;
  @override
  @JsonKey(name: 'user_audio_url')
  final String? userAudioUrl;
  final List<PhonemeError> _phonemeErrors;
  @override
  @JsonKey(name: 'phoneme_errors')
  List<PhonemeError> get phonemeErrors {
    if (_phonemeErrors is EqualUnmodifiableListView) return _phonemeErrors;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_phonemeErrors);
  }

  /// Create a copy of WordVerdict
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$WordVerdictCopyWith<_WordVerdict> get copyWith =>
      __$WordVerdictCopyWithImpl<_WordVerdict>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$WordVerdictToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _WordVerdict &&
            (identical(other.word, word) || other.word == word) &&
            (identical(other.wordIndex, wordIndex) ||
                other.wordIndex == wordIndex) &&
            (identical(other.isCorrect, isCorrect) ||
                other.isCorrect == isCorrect) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            (identical(other.expectedText, expectedText) ||
                other.expectedText == expectedText) &&
            (identical(other.actualText, actualText) ||
                other.actualText == actualText) &&
            (identical(other.errorType, errorType) ||
                other.errorType == errorType) &&
            (identical(other.errorDescription, errorDescription) ||
                other.errorDescription == errorDescription) &&
            (identical(other.referenceAudioUrl, referenceAudioUrl) ||
                other.referenceAudioUrl == referenceAudioUrl) &&
            (identical(other.userAudioUrl, userAudioUrl) ||
                other.userAudioUrl == userAudioUrl) &&
            const DeepCollectionEquality()
                .equals(other._phonemeErrors, _phonemeErrors));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      word,
      wordIndex,
      isCorrect,
      confidence,
      expectedText,
      actualText,
      errorType,
      errorDescription,
      referenceAudioUrl,
      userAudioUrl,
      const DeepCollectionEquality().hash(_phonemeErrors));

  @override
  String toString() {
    return 'WordVerdict(word: $word, wordIndex: $wordIndex, isCorrect: $isCorrect, confidence: $confidence, expectedText: $expectedText, actualText: $actualText, errorType: $errorType, errorDescription: $errorDescription, referenceAudioUrl: $referenceAudioUrl, userAudioUrl: $userAudioUrl, phonemeErrors: $phonemeErrors)';
  }
}

/// @nodoc
abstract mixin class _$WordVerdictCopyWith<$Res>
    implements $WordVerdictCopyWith<$Res> {
  factory _$WordVerdictCopyWith(
          _WordVerdict value, $Res Function(_WordVerdict) _then) =
      __$WordVerdictCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String word,
      @JsonKey(name: 'word_index') int wordIndex,
      @JsonKey(name: 'is_correct') bool isCorrect,
      @JsonKey(name: 'confidence') double confidence,
      @JsonKey(name: 'expected_text') String? expectedText,
      @JsonKey(name: 'actual_text') String? actualText,
      @JsonKey(name: 'error_type') String? errorType,
      @JsonKey(name: 'error_description') String? errorDescription,
      @JsonKey(name: 'reference_audio_url') String? referenceAudioUrl,
      @JsonKey(name: 'user_audio_url') String? userAudioUrl,
      @JsonKey(name: 'phoneme_errors') List<PhonemeError> phonemeErrors});
}

/// @nodoc
class __$WordVerdictCopyWithImpl<$Res> implements _$WordVerdictCopyWith<$Res> {
  __$WordVerdictCopyWithImpl(this._self, this._then);

  final _WordVerdict _self;
  final $Res Function(_WordVerdict) _then;

  /// Create a copy of WordVerdict
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? word = null,
    Object? wordIndex = null,
    Object? isCorrect = null,
    Object? confidence = null,
    Object? expectedText = freezed,
    Object? actualText = freezed,
    Object? errorType = freezed,
    Object? errorDescription = freezed,
    Object? referenceAudioUrl = freezed,
    Object? userAudioUrl = freezed,
    Object? phonemeErrors = null,
  }) {
    return _then(_WordVerdict(
      word: null == word
          ? _self.word
          : word // ignore: cast_nullable_to_non_nullable
              as String,
      wordIndex: null == wordIndex
          ? _self.wordIndex
          : wordIndex // ignore: cast_nullable_to_non_nullable
              as int,
      isCorrect: null == isCorrect
          ? _self.isCorrect
          : isCorrect // ignore: cast_nullable_to_non_nullable
              as bool,
      confidence: null == confidence
          ? _self.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double,
      expectedText: freezed == expectedText
          ? _self.expectedText
          : expectedText // ignore: cast_nullable_to_non_nullable
              as String?,
      actualText: freezed == actualText
          ? _self.actualText
          : actualText // ignore: cast_nullable_to_non_nullable
              as String?,
      errorType: freezed == errorType
          ? _self.errorType
          : errorType // ignore: cast_nullable_to_non_nullable
              as String?,
      errorDescription: freezed == errorDescription
          ? _self.errorDescription
          : errorDescription // ignore: cast_nullable_to_non_nullable
              as String?,
      referenceAudioUrl: freezed == referenceAudioUrl
          ? _self.referenceAudioUrl
          : referenceAudioUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      userAudioUrl: freezed == userAudioUrl
          ? _self.userAudioUrl
          : userAudioUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      phonemeErrors: null == phonemeErrors
          ? _self._phonemeErrors
          : phonemeErrors // ignore: cast_nullable_to_non_nullable
              as List<PhonemeError>,
    ));
  }
}

/// @nodoc
mixin _$PhonemeError {
  String get phoneme;
  @JsonKey(name: 'expected_phoneme')
  String get expectedPhoneme;
  @JsonKey(name: 'actual_phoneme')
  String get actualPhoneme;
  @JsonKey(name: 'position')
  int get position;
  @JsonKey(name: 'severity')
  String get severity;

  /// Create a copy of PhonemeError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $PhonemeErrorCopyWith<PhonemeError> get copyWith =>
      _$PhonemeErrorCopyWithImpl<PhonemeError>(
          this as PhonemeError, _$identity);

  /// Serializes this PhonemeError to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is PhonemeError &&
            (identical(other.phoneme, phoneme) || other.phoneme == phoneme) &&
            (identical(other.expectedPhoneme, expectedPhoneme) ||
                other.expectedPhoneme == expectedPhoneme) &&
            (identical(other.actualPhoneme, actualPhoneme) ||
                other.actualPhoneme == actualPhoneme) &&
            (identical(other.position, position) ||
                other.position == position) &&
            (identical(other.severity, severity) ||
                other.severity == severity));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, phoneme, expectedPhoneme, actualPhoneme, position, severity);

  @override
  String toString() {
    return 'PhonemeError(phoneme: $phoneme, expectedPhoneme: $expectedPhoneme, actualPhoneme: $actualPhoneme, position: $position, severity: $severity)';
  }
}

/// @nodoc
abstract mixin class $PhonemeErrorCopyWith<$Res> {
  factory $PhonemeErrorCopyWith(
          PhonemeError value, $Res Function(PhonemeError) _then) =
      _$PhonemeErrorCopyWithImpl;
  @useResult
  $Res call(
      {String phoneme,
      @JsonKey(name: 'expected_phoneme') String expectedPhoneme,
      @JsonKey(name: 'actual_phoneme') String actualPhoneme,
      @JsonKey(name: 'position') int position,
      @JsonKey(name: 'severity') String severity});
}

/// @nodoc
class _$PhonemeErrorCopyWithImpl<$Res> implements $PhonemeErrorCopyWith<$Res> {
  _$PhonemeErrorCopyWithImpl(this._self, this._then);

  final PhonemeError _self;
  final $Res Function(PhonemeError) _then;

  /// Create a copy of PhonemeError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? phoneme = null,
    Object? expectedPhoneme = null,
    Object? actualPhoneme = null,
    Object? position = null,
    Object? severity = null,
  }) {
    return _then(_self.copyWith(
      phoneme: null == phoneme
          ? _self.phoneme
          : phoneme // ignore: cast_nullable_to_non_nullable
              as String,
      expectedPhoneme: null == expectedPhoneme
          ? _self.expectedPhoneme
          : expectedPhoneme // ignore: cast_nullable_to_non_nullable
              as String,
      actualPhoneme: null == actualPhoneme
          ? _self.actualPhoneme
          : actualPhoneme // ignore: cast_nullable_to_non_nullable
              as String,
      position: null == position
          ? _self.position
          : position // ignore: cast_nullable_to_non_nullable
              as int,
      severity: null == severity
          ? _self.severity
          : severity // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [PhonemeError].
extension PhonemeErrorPatterns on PhonemeError {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_PhonemeError value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _PhonemeError() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_PhonemeError value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PhonemeError():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_PhonemeError value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PhonemeError() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            String phoneme,
            @JsonKey(name: 'expected_phoneme') String expectedPhoneme,
            @JsonKey(name: 'actual_phoneme') String actualPhoneme,
            @JsonKey(name: 'position') int position,
            @JsonKey(name: 'severity') String severity)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _PhonemeError() when $default != null:
        return $default(_that.phoneme, _that.expectedPhoneme,
            _that.actualPhoneme, _that.position, _that.severity);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            String phoneme,
            @JsonKey(name: 'expected_phoneme') String expectedPhoneme,
            @JsonKey(name: 'actual_phoneme') String actualPhoneme,
            @JsonKey(name: 'position') int position,
            @JsonKey(name: 'severity') String severity)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PhonemeError():
        return $default(_that.phoneme, _that.expectedPhoneme,
            _that.actualPhoneme, _that.position, _that.severity);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            String phoneme,
            @JsonKey(name: 'expected_phoneme') String expectedPhoneme,
            @JsonKey(name: 'actual_phoneme') String actualPhoneme,
            @JsonKey(name: 'position') int position,
            @JsonKey(name: 'severity') String severity)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PhonemeError() when $default != null:
        return $default(_that.phoneme, _that.expectedPhoneme,
            _that.actualPhoneme, _that.position, _that.severity);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _PhonemeError implements PhonemeError {
  const _PhonemeError(
      {required this.phoneme,
      @JsonKey(name: 'expected_phoneme') required this.expectedPhoneme,
      @JsonKey(name: 'actual_phoneme') required this.actualPhoneme,
      @JsonKey(name: 'position') required this.position,
      @JsonKey(name: 'severity') this.severity = 'minor'});
  factory _PhonemeError.fromJson(Map<String, dynamic> json) =>
      _$PhonemeErrorFromJson(json);

  @override
  final String phoneme;
  @override
  @JsonKey(name: 'expected_phoneme')
  final String expectedPhoneme;
  @override
  @JsonKey(name: 'actual_phoneme')
  final String actualPhoneme;
  @override
  @JsonKey(name: 'position')
  final int position;
  @override
  @JsonKey(name: 'severity')
  final String severity;

  /// Create a copy of PhonemeError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$PhonemeErrorCopyWith<_PhonemeError> get copyWith =>
      __$PhonemeErrorCopyWithImpl<_PhonemeError>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$PhonemeErrorToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _PhonemeError &&
            (identical(other.phoneme, phoneme) || other.phoneme == phoneme) &&
            (identical(other.expectedPhoneme, expectedPhoneme) ||
                other.expectedPhoneme == expectedPhoneme) &&
            (identical(other.actualPhoneme, actualPhoneme) ||
                other.actualPhoneme == actualPhoneme) &&
            (identical(other.position, position) ||
                other.position == position) &&
            (identical(other.severity, severity) ||
                other.severity == severity));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, phoneme, expectedPhoneme, actualPhoneme, position, severity);

  @override
  String toString() {
    return 'PhonemeError(phoneme: $phoneme, expectedPhoneme: $expectedPhoneme, actualPhoneme: $actualPhoneme, position: $position, severity: $severity)';
  }
}

/// @nodoc
abstract mixin class _$PhonemeErrorCopyWith<$Res>
    implements $PhonemeErrorCopyWith<$Res> {
  factory _$PhonemeErrorCopyWith(
          _PhonemeError value, $Res Function(_PhonemeError) _then) =
      __$PhonemeErrorCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String phoneme,
      @JsonKey(name: 'expected_phoneme') String expectedPhoneme,
      @JsonKey(name: 'actual_phoneme') String actualPhoneme,
      @JsonKey(name: 'position') int position,
      @JsonKey(name: 'severity') String severity});
}

/// @nodoc
class __$PhonemeErrorCopyWithImpl<$Res>
    implements _$PhonemeErrorCopyWith<$Res> {
  __$PhonemeErrorCopyWithImpl(this._self, this._then);

  final _PhonemeError _self;
  final $Res Function(_PhonemeError) _then;

  /// Create a copy of PhonemeError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? phoneme = null,
    Object? expectedPhoneme = null,
    Object? actualPhoneme = null,
    Object? position = null,
    Object? severity = null,
  }) {
    return _then(_PhonemeError(
      phoneme: null == phoneme
          ? _self.phoneme
          : phoneme // ignore: cast_nullable_to_non_nullable
              as String,
      expectedPhoneme: null == expectedPhoneme
          ? _self.expectedPhoneme
          : expectedPhoneme // ignore: cast_nullable_to_non_nullable
              as String,
      actualPhoneme: null == actualPhoneme
          ? _self.actualPhoneme
          : actualPhoneme // ignore: cast_nullable_to_non_nullable
              as String,
      position: null == position
          ? _self.position
          : position // ignore: cast_nullable_to_non_nullable
              as int,
      severity: null == severity
          ? _self.severity
          : severity // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
