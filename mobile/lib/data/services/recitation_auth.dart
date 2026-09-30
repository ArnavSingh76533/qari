import '../../core/constants/app_constants.dart';

/// Recorded audio is private. Only send the bearer to this API's audio route;
/// Quran reference audio on a public CDN must never receive a user's token.
Map<String, String> recitationAudioHeaders(String url, String? token,
    {String? apiBaseUrl}) {
  final base = Uri.parse(apiBaseUrl ?? AppConstants.baseUrl);
  final uri = Uri.tryParse(url);
  final prefix = base.path.replaceFirst(RegExp(r'/$'), '');
  if (uri == null ||
      token == null ||
      token.trim().isEmpty ||
      uri.scheme != base.scheme ||
      uri.host != base.host ||
      uri.port != base.port ||
      !RegExp('^${RegExp.escape(prefix)}/recitations/[^/]+/audio\$')
          .hasMatch(uri.path)) {
    return const {};
  }
  return {'Authorization': 'Bearer $token'};
}
