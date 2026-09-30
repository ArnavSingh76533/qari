import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_constants.dart';
import '../models/recitation_stream_event.dart';
import 'local_storage_service.dart';

/// Native side-channel to the `MicForegroundService` (microphone-typed Android
/// foreground service). Starting it is what makes the OS grant capture focus on
/// Android 14+; it is non-fatal if it fails (capture is still attempted).
const MethodChannel _micForegroundChannel =
    MethodChannel('com.qari.app/mic_foreground');

/// PCM16 audio frames captured natively inside the foreground service.
const EventChannel _micStreamChannel = EventChannel('com.qari.app/mic_stream');

/// Status / error text from the native capture (e.g. "capture started:
/// rate=16000", "capture error: ..."), surfaced live in the diag line.
const EventChannel _micStatusChannel = EventChannel('com.qari.app/mic_status');

/// Connection state of a live recitation streaming session.
enum LiveConnectionState { idle, connecting, listening, finishing, closed, error }

/// Streams microphone audio continuously to the backend `/ws/recitation/stream`
/// WebSocket and surfaces real-time word-by-word match events.
///
/// This powers the upgraded AI Recitation section (real-time tracking +
/// Memorization Mode). It is completely separate from [RecordingService]
/// (single-file record → upload), so the Quran reader's per-ayah "Recite" flow
/// is unaffected.
class StreamingRecitationService {
  WebSocket? _socket;
  StreamSubscription<dynamic>? _audioSub;
  StreamSubscription? _socketSub;
  /// Subscription to the native mic *status* channel (capture started / errors),
  /// surfaced live in the diag line so a swallowed native failure is visible.
  StreamSubscription? _statusSub;
  Timer? _pingTimer;

  /// Android audio session (via `audio_session`) activated before capture to
  /// request focus + speech attributes — helps the OS route the mic on devices
  /// that otherwise deliver silence despite the app permission being granted.
  AudioSession? _audioSession;

  /// Whether Android granted audio focus when we activated the session.
  /// `null` until activation finishes; `false` means the OS denied focus — a
  /// strong signal that another app holds the mic (or the OS is suppressing
  /// capture), which produces exactly the silent 0-frame stream behind
  /// "mic chunks: 0 · bytes sent: 0". Surfaced live in the diag line so a
  /// focus denial is visible immediately instead of being guessed at.
  bool? _audioFocusGranted;

  /// Latest native capture status string (e.g. "capture started: rate=16000",
  /// "capture error: ..."). Surfaced live in the diag line.
  String? _nativeStatus;

  /// Buffered PCM16 audio. Frames are cut on SIZE, not on a timer: whenever at
  /// least [_pcmFrameBytes] bytes are available they are sent IMMEDIATELY as one
  /// frame (see [_pumpFrames]).
  ///
  /// The previous implementation accumulated everything and flushed the whole
  /// buffer on a 250 ms timer, which shipped 250 ms-plus blobs (and, with a
  /// slower native cadence, 1-2 s blobs) — that client-side buffering was
  /// added straight on top of the server's own analysis window and showed up as
  /// "the words appear long after I said them". The backend needs a steady
  /// 100 ms cadence, not batched audio.
  /// Pending PCM16 bytes not yet framed.
  ///
  /// A plain growable list (not a [BytesBuilder]) because the pump needs to cut
  /// an EXACT [_pcmFrameBytes] slice and keep the remainder; BytesBuilder can
  /// only hand back everything it holds. At 3200-byte frames the copying here
  /// is negligible compared with a Whisper decode.
  final List<int> _pendingAudio = <int>[];

  /// One frame of PCM16 mono 16 kHz audio = 100 ms.
  /// 16000 samples/s x 2 bytes x 0.1 s = 3200 bytes.
  static const int _pcmFrameBytes = 3200;

  /// Safety-net timer. Frames are normally cut the instant they are complete, so
  /// this only exists to release a PARTIAL trailing frame (a 40 ms tail would
  /// otherwise sit in the buffer). It is deliberately short so it can never
  /// become the thing that batches the stream.
  Timer? _flushTimer;
  static const Duration _flushInterval = Duration(milliseconds: 100);

  /// Exposed for the framing contract test so the shipped constants (not a
  /// duplicated copy in the test) are what gets asserted.
  @visibleForTesting
  static int get pcmFrameBytesForTest => _pcmFrameBytes;

  @visibleForTesting
  static Duration get flushIntervalForTest => _flushInterval;

  final StreamController<RecitationStreamEvent> _events =
      StreamController<RecitationStreamEvent>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();
  final StreamController<LiveConnectionState> _connection =
      StreamController<LiveConnectionState>.broadcast();

  Completer<RecitationStreamEvent?>? _finalCompleter;
  LiveConnectionState _state = LiveConnectionState.idle;

  /// Total PCM bytes sent to the server (for debugging the "Duration: 0s" bug).
  int _totalSentBytes = 0;
  int _chunkCount = 0;
  DateTime? _firstChunkAt;

  /// Real-time backend events (ready / word / final / error).
  Stream<RecitationStreamEvent> get events => _events.stream;

  /// Normalized (0–1) mic loudness per audio chunk for the live visualizer.
  Stream<double> get amplitude => _amplitude.stream;

  /// Connection lifecycle updates.
  Stream<LiveConnectionState> get connectionState => _connection.stream;

  LiveConnectionState get state => _state;
  bool get isActive =>
      _state == LiveConnectionState.listening ||
      _state == LiveConnectionState.connecting;

  /// Total PCM bytes sent to the server so far (0 ⇒ no mic audio captured /
  /// no binary frames delivered → "Duration: 0s"). Exposed for live diagnostics.
  int get sentBytes => _totalSentBytes;

  /// Number of microphone chunks received from the recorder (0 ⇒ the recorder
  /// is producing no data → OS blocked capture despite the permission).
  int get micChunks => _chunkCount;

  /// Last native recorder error (if any). Surfaced live in the diag line.
  String? _micError;
  String? get micError => _micError;

  /// On-screen diagnostics for the native→Dart audio delivery, so we can debug
  /// the "mic chunks: 0" case without `flutter logs` (useful on a phone with no
  /// dev machine). Counts how many native audio frames actually reached the Dart
  /// `onData` callback (vs `_chunkCount`, which counts successfully processed).
  int _audioOnDataCount = 0;
  int get audioOnDataCount => _audioOnDataCount;
  String? _lastFrameType;
  String? get lastFrameType => _lastFrameType;
  String? _audioOnDataError;
  String? get audioOnDataError => _audioOnDataError;


  /// Result of the Android audio-focus request (via `audio_session`). `null`
  /// until the session is activated; `false` means the OS denied focus, which
  /// on many ROMs yields a silently-dead recorder (0 chunks, 0 errors) — the
  /// exact symptom behind "mic chunks: 0 · bytes sent: 0".
  bool? get audioFocusGranted => _audioFocusGranted;

  /// Latest native capture status (e.g. "capture started: rate=16000",
  /// "capture error: ..."). Surfaced live in the diag line.
  String? get nativeStatus => _nativeStatus;

  void _setState(LiveConnectionState s) {
    _state = s;
    if (!_connection.isClosed) _connection.add(s);
  }

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Opens the WebSocket, sends the `start` handshake, and begins streaming
  /// microphone audio. Throws on permission denial or connection failure.
  ///
  /// [ayahRefs] is the explicit ordered list of `(surah, ayah)` the user will
  /// recite continuously (a full Mushaf page or a whole surah). When omitted we
  /// fall back to a single-surah range built from [surahNumber]/[ayahNumber].
  Future<void> start({
    required int surahNumber,
    required int ayahNumber,
    int? ayahFrom,
    int? ayahTo,
    List<(int, int)>? ayahRefs,
    required bool memorizationMode,
    List<String>? words,
  }) async {
    if (isActive) return;
    _setState(LiveConnectionState.connecting);
    _totalSentBytes = 0;
    _chunkCount = 0;
    _audioOnDataCount = 0;
    _lastFrameType = null;
    _audioOnDataError = null;
    _micError = null;
    _audioFocusGranted = null;
    _firstChunkAt = null;

    final token = await LocalStorageService().getAuthToken();
    if (token == null || token.trim().isEmpty) {
      _setState(LiveConnectionState.error);
      throw StreamingConnectionException('Sign in to start reciting.');
    }

    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) {
        _setState(LiveConnectionState.error);
        throw const MicPermissionDeniedException();
      }
    }
    _audioSession?.setActive(false).catchError((_) => false);
    _audioSession = null;

    // --- Connect the WebSocket (trust the VPS self-signed cert) ---
    final wsUrl = AppConstants.recitationStreamWsUrl;
    final httpClient = HttpClient()
      ..badCertificateCallback =
          (cert, host, port) => host == AppConstants.trustedSelfSignedHost;
    try {
      debugPrint('[Streaming] connecting to $wsUrl');
      _socket = await WebSocket.connect(
        wsUrl,
        customClient: httpClient,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        throw StreamingConnectionException('WebSocket connect timed out');
      });
    } catch (e) {
      _setState(LiveConnectionState.error);
      debugPrint('[Streaming] WS CONNECT FAILED: $e');
      throw StreamingConnectionException('Could not connect: $e');
    }

    _socketSub = _socket!.listen(
      _onSocketData,
      onError: (Object e, StackTrace? st) {
        // A WebSocket-level error (handshake failure, 400/500, dropped
        // connection). Surface it loudly so "Duration 0s" can be diagnosed.
        debugPrint('[Streaming] WS ERROR: $e');
        if (st != null) debugPrint('$st');
        _setState(LiveConnectionState.error);
      },
      onDone: () {
        debugPrint('[Streaming] WS CLOSED (done). state=${_state.name}');
        if (_state != LiveConnectionState.finishing) {
          _setState(LiveConnectionState.closed);
        }
      },
      cancelOnError: false,
    );

    // --- Handshake ---
    // Send the explicit ordered ayah sequence so the backend can resolve the
    // concatenated reference list and track words seamlessly across ayah
    // boundaries (full-page / full-surah continuous recitation). Also send the
    // client's resolved word list as a fallback reference so the backend can
    // still score when its own reference store is empty (prevents "0 of 0").
    final List<List<int>> refs = ayahRefs == null
        ? []
        : ayahRefs.map((r) => [r.$1, r.$2]).toList();
    _socket!.add(jsonEncode({
      'type': 'start',
      'surah_number': surahNumber,
      'ayah_number': ayahNumber,
      'ayah_from': ayahFrom ?? ayahNumber,
      'ayah_to': ayahTo ?? ayahNumber,
      if (refs.isNotEmpty) 'ayahs': refs,
      if (words != null && words.isNotEmpty) 'words': words,
      'mode': memorizationMode ? 'memorization' : 'tracking',
      'sample_rate': AppConstants.liveRecitationSampleRate,
    }));
    debugPrint('[Streaming] sent start handshake '
        '(surah=$surahNumber, ayah=$ayahNumber, refs=${refs.length}, '
        'clientWords=${(words?.length) ?? 0})');

    // --- Start the continuous PCM audio stream (native, inside the mic
    // foreground service). The `record` plugin opens AudioRecord on the Flutter
    // engine thread, outside the foreground-service capture context, so on
    // Android 14+ it can be granted focus yet receive 0 frames. Capturing
    // natively inside the service is the sanctioned fix.
    await _activateAudioSession();
    // Subscribe to the native mic stream BEFORE starting the foreground service
    // so the Flutter EventChannel listener is attached and `audioSink` is set on
    // the native side *before* the service begins producing + flushing frames.
    // Otherwise the first frames are flushed into a null sink and (previously)
    // dropped → "mic chunks: 0 · bytes sent: 0".
    try {
      _subscribeNativeMic();
      debugPrint('[Streaming] native mic stream SUBSCRIBED.');
    } on MicPermissionDeniedException {
      rethrow;
    } catch (e, st) {
      _micError = e.toString();
      debugPrint('[Streaming] native mic subscribe FAILED: $e\n$st');
      _setState(LiveConnectionState.error);
      throw StreamingConnectionException('Mic could not start: $e');
    }
    // Start the microphone foreground service so the OS grants capture focus on
    // Android 14+ (fixes the "mic chunks: 0 / focus: NO" silent-capture case).
    await _startForegroundMicService();

    // --- Keep-alive pings so long hands-free sessions never drop ---
    _pingTimer = Timer.periodic(
      const Duration(seconds: AppConstants.liveRecitationPingIntervalSeconds),
      (_) {
        final sock = _socket;
        if (sock != null && sock.readyState == WebSocket.open) {
          sock.add(jsonEncode({'type': 'ping'}));
        }
      },
    );

    // --- Chunked upload: size-driven 100 ms frames -------------------------
    // The timer is only a partial-tail safety net; complete frames are sent by
    // _pumpFrames the moment they form (see _onNativeAudio).
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      _flushAudio();
    });

    _setState(LiveConnectionState.listening);
    debugPrint('StreamingRecitation: streaming started (sentBytes tracked)');
  }

  /// Starts the native microphone foreground service (Android 14+). Non-fatal:
  /// if it fails we still try to record — but without it the OS denies capture
  /// focus (the "mic chunks: 0 / focus: NO" failure).
  Future<void> _startForegroundMicService() async {
    try {
      await _micForegroundChannel.invokeMethod<void>('start');
      debugPrint('[Streaming] mic foreground service started.');
    } catch (e) {
      debugPrint('[Streaming] mic foreground service start failed (non-fatal): $e');
    }
  }

  /// Stops the native microphone foreground service.
  Future<void> _stopForegroundMicService() async {
    try {
      await _micForegroundChannel.invokeMethod<void>('stop');
      debugPrint('[Streaming] mic foreground service stopped.');
    } catch (e) {
      debugPrint('[Streaming] mic foreground service stop failed (non-fatal): $e');
    }
  }

  /// Requests Android audio focus + configures a speech/record audio session so
  /// the OS routes the mic to this app. Non-fatal: if it fails we still try to
  /// record (some devices don't need it; a failure here is not the capture bug).
  Future<void> _activateAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidWillPauseWhenDucked: false,
      ));
      // `setActive` returns whether the OS actually granted focus. A `false`
      // here (or a throw) means the mic is contended/blocked — capture it so
      // the UI can show "focus: NO" instead of a bare 0-chunk stream.
      final granted = await session.setActive(true);
      _audioFocusGranted = granted;
      _audioSession = session;
      debugPrint('[Streaming] audio session activated '
          '(focus granted: $granted).');
    } catch (e) {
      _audioFocusGranted = false;
      debugPrint('[Streaming] audio session activate failed (non-fatal): $e');
    }
  }

  /// Subscribes to the native mic PCM stream + status channel. The status
  /// channel fires first ("capture started: rate=…" / "capture error: …") so a
  /// silently-dead capture is visible immediately instead of a bare "0 bytes".
  void _subscribeNativeMic() {
    _statusSub?.cancel();
    _statusSub = _micStatusChannel.receiveBroadcastStream().listen(
      (dynamic msg) {
        final s = msg is String ? msg : msg?.toString();
        if (s != null) {
          _nativeStatus = s;
          debugPrint('[Streaming] native mic status: $s');
          if (s.toLowerCase().contains('error')) _micError = s;
        }
      },
      onError: (Object e, StackTrace? st) {
        _micError = e.toString();
        debugPrint('[Streaming] native mic STATUS ERROR: $e');
        if (st != null) debugPrint('$st');
      },
      cancelOnError: false,
    );

    _audioSub = _micStreamChannel.receiveBroadcastStream().listen(
      (dynamic chunk) {
        _audioOnDataCount++;
        _lastFrameType = chunk.runtimeType.toString();
        try {
          debugPrint('[Streaming] native audio onData type=${chunk.runtimeType} '
              'len=${chunk is List ? chunk.length : 'n/a'}');
          Uint8List bytes;
          if (chunk is Uint8List) {
            bytes = chunk;
          } else if (chunk is List<int>) {
            bytes = Uint8List.fromList(chunk);
          } else {
            debugPrint('[Streaming] native audio UNKNOWN type, ignoring');
            return;
          }
          _onNativeAudio(bytes);
        } catch (e, st) {
          _audioOnDataError = e.toString();
          debugPrint('[Streaming] native audio onData ERROR: $e\n$st');
        }
      },
      onError: (Object e, StackTrace? st) {
        _micError = e.toString();
        debugPrint('[Streaming] native mic STREAM ERROR: $e');
        if (st != null) debugPrint('$st');
      },
      cancelOnError: false,
    );
  }

  /// Forwards a native PCM16 frame to the live visualizer + upload buffer.
  void _onNativeAudio(Uint8List chunk) {
    // Count + buffer the frame FIRST, before any amplitude math, so a failure in
    // RMS computation can never suppress chunk counting / server upload (that
    // was the "mic chunks: 0 · bytes sent: 0" despite 500+ frames arriving).
    _chunkCount++;
    _firstChunkAt ??= DateTime.now();
    if (chunk.isNotEmpty) {
      _pendingAudio.addAll(chunk);
      // Send every COMPLETE 100 ms frame right now. This is the whole point of
      // the fix: the server starts working on audio ~100 ms after it is spoken
      // instead of after an arbitrary client-side batching window.
      _pumpFrames();
    }
    if (_chunkCount <= 5 || _chunkCount % 50 == 0) {
      debugPrint('[Streaming] mic chunk #$_chunkCount '
          'len=${chunk.length} bytes (pending=${_pendingAudio.length})');
    }
    try {
      _emitAmplitude(chunk);
    } catch (e, st) {
      _audioOnDataError = e.toString();
      debugPrint('[Streaming] _emitAmplitude ERROR (chunk len=${chunk.length}): '
          '$e\n$st');
    }
  }

  /// Cuts and sends every COMPLETE [_pcmFrameBytes] frame sitting in the
  /// buffer, immediately. Any remainder (< one frame) is deliberately left for
  /// the safety-net timer so a partial tail is still delivered promptly.
  void _pumpFrames() {
    final sock = _socket;
    if (sock == null || sock.readyState != WebSocket.open) return;
    while (_pendingAudio.length >= _pcmFrameBytes) {
      final frame = Uint8List.fromList(_pendingAudio.sublist(0, _pcmFrameBytes));
      _pendingAudio.removeRange(0, _pcmFrameBytes);
      _totalSentBytes += frame.length;
      sock.add(frame);
    }
  }

  /// Safety-net flush: releases any PARTIAL trailing frame the size-driven pump
  /// could not send, so the last few tens of milliseconds before a stop are not
  /// stranded. Never used to batch a normal stream.
  void _flushAudio() {
    _pumpFrames();
    if (_pendingAudio.isEmpty) return;
    final sock = _socket;
    if (sock != null && sock.readyState == WebSocket.open) {
      final frame = Uint8List.fromList(_pendingAudio);
      _pendingAudio.clear();
      _totalSentBytes += frame.length;
      sock.add(frame);
      debugPrint('[Streaming] TAIL FLUSH -> sent ${frame.length} bytes '
          '(totalSent=$_totalSentBytes)');
    } else {
      debugPrint('[Streaming] TAIL FLUSH skipped: socket not open '
          '(state=${_state.name}, pending=${_pendingAudio.length})');
      _pendingAudio.clear();
    }
  }

  void _onSocketData(dynamic data) {
    if (data is! String) {
      debugPrint('[Streaming] received non-string frame (ignored).');
      return;
    }
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final event = RecitationStreamEvent.fromJson(json);
      if (event.type == RecitationStreamEventType.word) {
        debugPrint('[Streaming] RX word event idx=${event.wordIndex} '
            'status=${event.status.name} expected=${event.expected}');
      } else if (event.type == RecitationStreamEventType.ready) {
        debugPrint('[Streaming] RX ready (${event.words.length} words)');
      } else if (event.type == RecitationStreamEventType.finalResult) {
        debugPrint('[Streaming] RX final (duration=${event.result?.durationSeconds}s, '
            'verdicts=${event.result?.wordVerdicts.length})');
      } else if (event.type == RecitationStreamEventType.error) {
        debugPrint('[Streaming] RX ERROR: ${event.detail}');
      }
      if (!_events.isClosed) _events.add(event);
      if (event.type == RecitationStreamEventType.finalResult) {
        _finalCompleter?.complete(event);
        _finalCompleter = null;
      }
    } catch (e) {
      debugPrint('[Streaming] decode error: $e');
    }
  }

  /// Computes an RMS loudness (0–1) from a PCM16 little-endian chunk.
  void _emitAmplitude(Uint8List chunk) {
    if (chunk.length < 2) return;
    // The incoming `Uint8List` is often a VIEW (`_Uint8ArrayView`) with an odd
    // `offsetInBytes` into a larger buffer. `buffer.asInt16List(offset, n)`
    // throws RangeError when `offset` is not a multiple of 2 — and that throw
    // happened here on every frame, skipping `_chunkCount++` and leaving the
    // whole session at "mic chunks: 0 · bytes sent: 0" despite 500+ native
    // frames arriving (onData: N). Read the samples manually via byte indexing
    // so alignment can never throw.
    final sampleCount = chunk.length ~/ 2; // drop a trailing odd byte
    if (sampleCount == 0) return;
    var sumSq = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final lo = chunk[i * 2];
      final hi = chunk[i * 2 + 1];
      // little-endian 16-bit signed
      final s = (hi << 8) | lo;
      final v = (s >= 0x8000 ? s - 0x10000 : s) / 32768.0;
      sumSq += v * v;
    }
    final rms = math.sqrt(sumSq / sampleCount);
    // Map RMS to a lively 0–1 range (recitation is fairly quiet at the mic).
    final normalized = (rms * 3.2).clamp(0.0, 1.0);
    if (!_amplitude.isClosed) _amplitude.add(normalized);
  }

  /// Stops recording, tells the backend to finalize, and awaits the final
  /// result (bounded by [timeout]). Returns the final result event if received.
  /// IMPORTANT: the caller must NOT navigate to results until this resolves —
  /// it blocks until the server sends the aggregated `final` payload.
  Future<RecitationStreamEvent?> stop({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_state == LiveConnectionState.idle ||
        _state == LiveConnectionState.closed) {
      debugPrint('[Streaming] stop() called but session not active '
          '(state=${_state.name}) — nothing to finalize.');
      return null;
    }
    _setState(LiveConnectionState.finishing);

    // Stop capturing audio first.
    await _audioSub?.cancel();
    _audioSub = null;
    await _statusSub?.cancel();
    _statusSub = null;
    _pingTimer?.cancel();
    _flushTimer?.cancel();
    _flushAudio(); // send any trailing audio before finalizing

    debugPrint('[Streaming] requesting finalize from server '
        '(totalSentBytes=$_totalSentBytes, micChunks=$_chunkCount)');

    _finalCompleter = Completer<RecitationStreamEvent?>();
    final sock = _socket;
    if (sock != null && sock.readyState == WebSocket.open) {
      sock.add(jsonEncode({'type': 'stop'}));
    } else {
      debugPrint('[Streaming] cannot send stop: socket not open '
          '(state=${_state.name})');
      _finalCompleter?.complete(null);
    }

    RecitationStreamEvent? finalEvent;
    try {
      finalEvent = await _finalCompleter!.future.timeout(timeout);
    } on TimeoutException {
      debugPrint('[Streaming] TIMEOUT waiting for server final result '
          '(server did not respond in ${timeout.inSeconds}s).');
    } finally {
      _finalCompleter = null;
      await _closeSocket();
      _setState(LiveConnectionState.closed);
    }

    final r = finalEvent?.result;
    debugPrint('[Streaming] FINAL result received: '
        'duration=${r?.durationSeconds}s, '
        'verdicts=${r?.wordVerdicts.length}, '
        'score=${r?.overallScore}');
    return finalEvent;
  }

  /// Aborts the session without waiting for a final result.
  Future<void> cancel() async {
    _pingTimer?.cancel();
    _flushTimer?.cancel();
    _pendingAudio.clear();
    await _audioSub?.cancel();
    _audioSub = null;
    await _statusSub?.cancel();
    _statusSub = null;
    await _closeSocket();
    _setState(LiveConnectionState.closed);
  }

  /// Releases the Android audio focus / speech session acquired in
  /// [_activateAudioSession]. Best-effort and non-fatal.
  void _deactivateAudioSession() {
    final session = _audioSession;
    _audioSession = null;
    _audioFocusGranted = null;
    if (session != null) {
      session.setActive(false).catchError((_) => false);
    }
  }

  Future<void> _closeSocket() async {
    _flushTimer?.cancel();
    _pingTimer?.cancel();
    _deactivateAudioSession();
    await _stopForegroundMicService();
    await _audioSub?.cancel();
    _audioSub = null;
    await _statusSub?.cancel();
    _statusSub = null;
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  Future<void> dispose() async {
    await cancel();
    await _events.close();
    await _amplitude.close();
    await _connection.close();
  }
}

/// Thrown when microphone permission is denied.
class MicPermissionDeniedException implements Exception {
  const MicPermissionDeniedException();
  @override
  String toString() => 'Microphone permission denied';
}

/// Thrown when the streaming WebSocket cannot be established.
class StreamingConnectionException implements Exception {
  final String message;
  const StreamingConnectionException(this.message);
  @override
  String toString() => message;
}
