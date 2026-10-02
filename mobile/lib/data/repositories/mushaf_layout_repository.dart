import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Authoritative printed locations, kept separate from immutable Quran text.
class MushafLocation {
  const MushafLocation(this.page, this.line);
  final int page;
  final int line;

  int get row => (page - 1) * 15 + line;
}

class MushafAyahLayout {
  const MushafAyahLayout(this.words, this.marker);
  final List<MushafLocation> words;
  final MushafLocation marker;
}

class MushafLayoutRepository {
  static Map<String, MushafAyahLayout>? _cached;

  Future<Map<String, MushafAyahLayout>> load() async {
    if (_cached != null) return _cached!;
    final layout = await _read();
    _cached = layout;
    return layout;
  }

  Future<Map<String, MushafAyahLayout>> _read() async {
    final data = await rootBundle.load('assets/mushaf_layout.json.gz');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final root =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    final verses = root['verses'] as Map<String, dynamic>;
    return verses.map((ref, raw) {
      final locations = (raw as List<dynamic>).map((pair) {
        final values = pair as List<dynamic>;
        return MushafLocation(values[0] as int, values[1] as int);
      }).toList();
      return MapEntry(
        ref,
        MushafAyahLayout(
          List.unmodifiable(locations.take(locations.length - 1)),
          locations.last,
        ),
      );
    });
  }
}
