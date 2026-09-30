import 'dart:io';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import 'local_storage_service.dart';
import 'recitation_auth.dart';

/// Audio service wrapping just_audio for Quran ayah playback.
/// Supports speed control, reciter selection, and audio session management.
class AudioService {
  /// Maps the app's reciter keys (stored via LocalStorageService) to the
  /// folder name used by the everyayah.com audio CDN.
  static const Map<String, String> _reciterFolders = {
    'abdul_basit': 'Abdul_Basit_Murattal_192kbps',
    'sudais': 'Abdurrahmaan_As-Sudais_192kbps',
    'minshawi': 'Minshawy_Murattal_128kbps',
    'husary': 'Husary_128kbps',
    'afasy': 'Alafasy_128kbps',
  };

  /// Falls back to Al-Afasy if an unknown reciter key is selected.
  static String _folderFor(String reciter) =>
      _reciterFolders[reciter] ?? 'Alafasy_128kbps';
  final AudioPlayer _player = AudioPlayer();
  final LocalStorageService _storage = LocalStorageService();

  bool _isInitialized = false;
  String _currentReciter = 'abdul_basit';
  double _currentSpeed = AppConstants.defaultPlaybackSpeed;
  String? _currentUrl;
  bool _isSequential = false;

  /// Cached probe result for the Urdu translation audio CDN. Null = not yet
  /// probed. We never assume the CDN is up: a dead Urdu URL concatenated into
  /// the playback queue makes just_audio throw and kills the WHOLE sequence
  /// (including Arabic), so we only enqueue Urdu audio once we've verified the
  /// source actually serves files.
  bool? _urduCdnAvailable;
  final Dio _probeDio = Dio();

  /// Whether the shared audio session has been (re)configured for MEDIA
  /// playback. The live recitation flow configures the process-wide
  /// `audio_session` for `voiceCommunication` (mic capture), which routes
  /// subsequent playback through the low-gain COMMUNICATION path — so a surah
  /// played afterwards is very quiet even at max media volume. We reconfigure
  /// the session for `media`/`music` before every playback to guarantee loud,
  /// media-stream output regardless of what a prior recitation left behind.
  AudioService() {
    _init();
  }

  Future<void> _init() async {
    if (_isInitialized) return;
    try {
      _currentReciter = await _storage.getSelectedQari();
      _isInitialized = true;
    } catch (e) {
      debugPrint('AudioService init error: $e');
    }
  }

  /// Configures the shared audio session for loud MEDIA playback and requests
  /// media audio focus. Idempotent-ish: always re-applies before playback so it
  /// overrides any `voiceCommunication` config left by the live recitation flow
  /// (the root cause of low surah volume). Non-fatal on failure.
  Future<void> _ensureMediaSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
      await session.setActive(true);
      // Ensure the player itself is at full volume (a prior ducking/attenuation
      // could have lowered it).
      await _player.setVolume(1.0);
    } catch (e) {
      debugPrint('AudioService media session config error: $e');
    }
  }

  AudioPlayer get player => _player;

  /// Builds the audio URL for a given surah and ayah.
  String buildAyahUrl({
    required int surahNumber,
    required int ayahNumber,
    String? reciter,
  }) {
    final folder = _folderFor(reciter ?? _currentReciter);
    final paddedSurah = surahNumber.toString().padLeft(3, '0');
    final paddedAyah = ayahNumber.toString().padLeft(3, '0');
    return '${AppConstants.audioCdnUrl}/$folder/$paddedSurah$paddedAyah.mp3';
  }

  /// Builds the Urdu translation audio URL for a given surah and ayah.
  ///
  /// Uses the everyayah.com Urdu tarjuma CDN ([AppConstants.urduTranslationCdnUrl])
  /// with the same 3-digit `{surah}{ayah}.mp3` layout as the Arabic recitation.
  /// Returns null if no Urdu CDN is configured.
  String? buildUrduTranslationUrl({
    required int surahNumber,
    required int ayahNumber,
  }) {
    if (AppConstants.urduTranslationCdnUrl.isEmpty) return null;
    final paddedSurah = surahNumber.toString().padLeft(3, '0');
    final paddedAyah = ayahNumber.toString().padLeft(3, '0');
    return '${AppConstants.urduTranslationCdnUrl}/$paddedSurah$paddedAyah.mp3';
  }

  /// Probes the Urdu translation audio CDN once and caches the result.
  ///
  /// Returns true only if the source actually serves audio for a sample ayah
  /// (1:1). When false, callers must NOT enqueue Urdu URLs — a dead URL in the
  /// concatenated playback queue makes just_audio throw and silently breaks all
  /// audio (Arabic included). A 404 here means the configured CDN is dead
  /// (e.g. the bundled `urdu_shamshad_ali_khan_46kbps` path is not hosted on
  /// everyayah.com) and the operator needs to point [AppConstants.urduTranslationCdnUrl]
  /// at a real, per-ayah Urdu audio source.
  Future<bool> isUrduTranslationAvailable() async {
    if (_urduCdnAvailable != null) return _urduCdnAvailable!;
    if (AppConstants.urduTranslationCdnUrl.isEmpty) {
      _urduCdnAvailable = false;
      return false;
    }
    final url = buildUrduTranslationUrl(surahNumber: 1, ayahNumber: 1);
    if (url == null) {
      _urduCdnAvailable = false;
      return false;
    }
    try {
      final resp = await _probeDio
          .get<Uint8List>(
            url,
            options: Options(
              headers: {'Range': 'bytes=0-1'},
              responseType: ResponseType.bytes,
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              // Accept any status so we can inspect the code ourselves.
              validateStatus: (_) => true,
            ),
          )
          .timeout(const Duration(seconds: 8));
      _urduCdnAvailable = resp.statusCode == 200 || resp.statusCode == 206;
    } catch (_) {
      _urduCdnAvailable = false;
    }
    return _urduCdnAvailable!;
  }

  /// Forces the next [isUrduTranslationAvailable] call to re-probe (e.g. after
  /// the operator updates [AppConstants.urduTranslationCdnUrl]).
  void resetUrduTranslationAvailability() => _urduCdnAvailable = null;

  /// Builds the audio URL for a full surah.
  String buildSurahUrl({
    required int surahNumber,
    String? reciter,
  }) {
    final folder = _folderFor(reciter ?? _currentReciter);
    final paddedSurah = surahNumber.toString().padLeft(3, '0');
    return '${AppConstants.audioCdnUrl}/$folder/$paddedSurah.mp3';
  }

  /// Plays a sequence of ayah URLs as one continuous, gapless track — i.e. the
  /// whole surah played in a single tap instead of one ayah at a time.
  ///
  /// [urls] is the ordered list of per-ayah audio URLs (e.g. the remaining
  /// ayahs of a surah). [initialIndex] lets playback start partway through the
  /// list (defaults to 0).
  Future<void> playSurahSequence({
    required List<String> urls,
    int initialIndex = 0,
  }) async {
    if (urls.isEmpty) return;
    debugPrint('AudioService: playing surah sequence (${urls.length} ayahs, '
        'start @ $initialIndex)');
    try {
      await _ensureMediaSession();
      final sources = urls
          .map((u) => AudioSource.uri(Uri.parse(u)))
          .toList(growable: false);
      final concat = ConcatenatingAudioSource(children: sources);
      await _player.setAudioSource(concat, initialIndex: initialIndex);
      await _player.setSpeed(_currentSpeed);
      await _player.play();
      _isSequential = true;
      _currentUrl = null;
    } catch (e) {
      debugPrint('AudioService playSurahSequence error: $e');
      rethrow;
    }
  }

  /// Stream of the index of the currently playing item within a sequential
  /// (whole-surah) queue. Emits null when not playing a sequence.
  Stream<int?> get currentIndexStream =>
      _player.sequenceStateStream.map((s) => s?.currentIndex);

  /// Whether a whole-surah sequence is currently loaded.
  bool get isSequential => _isSequential;

  /// Plays a single ayah audio.
  Future<void> playAyah({
    required int surahNumber,
    required int ayahNumber,
    String? reciter,
  }) async {
    final url = buildAyahUrl(
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      reciter: reciter,
    );
    await _playUrl(url);
  }

  /// Plays audio from a URL.
  Future<void> playUrl(String url) async {
    await _playUrl(url);
  }

  Future<void> _playUrl(String url) async {
    debugPrint('AudioService: playing url -> $url');
    try {
      if (_currentUrl == url && _player.playing) {
        await _player.pause();
        return;
      }
      await _ensureMediaSession();
      // The VPS uses a self-signed TLS cert. just_audio/ExoPlayer rejects it
      // for https media URLs (so comparison audio was silent). For the trusted
      // self-signed host we download via an HttpClient that accepts the cert,
      // cache it to a temp file, and play from there — avoiding the TLS error.
      final uri = Uri.parse(url);
      final headers = recitationAudioHeaders(url, await _storage.getAuthToken());
      if (headers.isNotEmpty) {
        final file = await _downloadToTemp(url, headers: headers);
        if (file == null) throw StateError('Could not load your recording. Sign in and try again.');
        await _player.setAudioSource(AudioSource.file(file.path));
        await _player.setSpeed(_currentSpeed);
        await _player.play();
        _currentUrl = url;
        _isSequential = false;
        return;
      }
      if (uri.scheme == 'https' &&
          uri.host == AppConstants.trustedSelfSignedHost) {
        final file = await _downloadToTemp(url);
        if (file != null) {
          await _player.setAudioSource(AudioSource.file(file.path));
          await _player.setSpeed(_currentSpeed);
          await _player.play();
          _currentUrl = url;
          _isSequential = false;
          return;
        }
        // Fall through to direct playback if download failed.
      }
      await _player.setAudioSource(AudioSource.uri(uri));
      await _player.setSpeed(_currentSpeed);
      await _player.play();
      _currentUrl = url;
      _isSequential = false;
    } catch (e) {
      debugPrint('AudioService play error: $e');
      rethrow;
    }
  }

  /// Downloads [url] over an HttpClient that trusts the VPS self-signed cert,
  /// returning a temp file, or null on failure.
  static Future<File?> _downloadToTemp(String url,
      {Map<String, String> headers = const {}}) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback =
            (cert, host, port) => host == AppConstants.trustedSelfSignedHost;
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach((key, value) => req.headers.set(key, value));
      // Owned recordings are served directly. Do not forward a JWT through a
      // redirect, even if a server accidentally returns a different origin.
      if (headers.isNotEmpty) req.followRedirects = false;
      final resp = await req.close();
      if (resp.statusCode != 200) {
        client.close();
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(resp);
      client.close();
      final tmp = File(
        '${(await getTemporaryDirectory()).path}/qari_audio_'
        '${url.hashCode}.wav',
      );
      await tmp.writeAsBytes(bytes);
      return tmp;
    } catch (e) {
      debugPrint('AudioService download error: $e');
      return null;
    }
  }

  /// Pauses playback.
  Future<void> pause() async {
    await _player.pause();
  }

  /// Resumes playback.
  Future<void> resume() async {
    await _player.play();
  }

  /// Stops playback and releases resources.
  Future<void> stop() async {
    await _player.stop();
    _currentUrl = null;
    _isSequential = false;
  }

  /// Seeks to a position in the audio.
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Sets the playback speed.
  Future<void> setSpeed(double speed) async {
    _currentSpeed = speed;
    await _player.setSpeed(speed);
  }

  /// Gets the current playback speed.
  double get currentSpeed => _currentSpeed;

  /// Sets the reciter.
  Future<void> setReciter(String reciter) async {
    _currentReciter = reciter;
    await _storage.setSelectedQari(reciter);
  }

  /// Gets the current reciter.
  String get currentReciter => _currentReciter;

  /// Whether audio is currently playing.
  bool get isPlaying => _player.playing;

  /// Current playback position.
  Stream<Duration> get positionStream => _player.positionStream;

  /// Total duration of the current audio.
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Player state stream.
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Disposes the audio player.
  void dispose() {
    _player.dispose();
  }
}
