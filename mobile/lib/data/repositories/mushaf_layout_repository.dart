import 'dart:convert';

import 'package:flutter/services.dart';

/// Printed line ends keyed by the existing corpus' body-word indices.
/// Text, verse markers and recitation indices remain in the corpus.
class MushafLayoutRepository {
  static Map<String, dynamic>? _pages;

  Future<List<int>> getLineEnds(int page) async {
    final pages = _pages ??= await _load();
    final ends = pages['$page'] as List<dynamic>?;
    return ends?.cast<int>() ?? const [];
  }

  static Future<Map<String, dynamic>> _load() async {
    final text = await rootBundle.loadString('assets/mushaf_line_ends.json');
    final root = jsonDecode(text) as Map<String, dynamic>;
    return root['pages'] as Map<String, dynamic>;
  }
}
