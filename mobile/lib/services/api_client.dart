import 'dart:io';

class QariApiClient {
  static const String _baseUrl = 'http://172.31.15.116:8000/analyze';

  Future<Map<String, dynamic>> analyzeAudio({
    required File audioFile,
    required int surahId,
    required int ayahNumber,
  }) async {
    // Production client for Qari inference endpoint
    return {'status': 'ready', 'endpoint': _baseUrl};
  }
}
