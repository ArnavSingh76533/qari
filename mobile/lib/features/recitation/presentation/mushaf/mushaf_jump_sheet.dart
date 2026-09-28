import 'package:flutter/material.dart';

import '../../../../data/repositories/local_corpus_repository.dart';
import 'mushaf_theme.dart';
import 'surah_titles.dart';

/// The value the picker applies when the user confirms.
class MushafJumpTarget {
  final int surah;
  final int ayahFrom;
  final int ayahTo;

  const MushafJumpTarget({
    required this.surah,
    required this.ayahFrom,
    required this.ayahTo,
  });
}

/// Bottom sheet that jumps the recitation to a chosen surah + ayah range.
///
/// Opens from the floating bar's quick-jump action. It resolves the surah's real
/// ayah count from the bundled corpus so the ayah pickers can never offer a
/// verse that does not exist, then hands the selection back via [onPick].
class MushafJumpSheet extends StatefulWidget {
  const MushafJumpSheet({
    super.key,
    required this.theme,
    required this.initialSurah,
    required this.initialAyahFrom,
    required this.initialAyahTo,
    required this.initialAyahCount,
    this.totalSurahs = 114,
    this.onPick,
  });

  final MushafTheme theme;
  final int initialSurah;
  final int initialAyahFrom;
  final int initialAyahTo;

  /// Ayah count of [initialSurah] when the caller already knows it (avoids a
  /// flash of a wrong count on open).
  final int initialAyahCount;

  final int totalSurahs;
  final ValueChanged<MushafJumpTarget>? onPick;

  /// Shows the sheet and returns the chosen target, or null if dismissed.
  static Future<MushafJumpTarget?> show(
    BuildContext context, {
    required MushafTheme theme,
    required int initialSurah,
    required int initialAyahFrom,
    required int initialAyahTo,
    required int initialAyahCount,
    int totalSurahs = 114,
  }) {
    return showModalBottomSheet<MushafJumpTarget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => MushafJumpSheet(
        theme: theme,
        initialSurah: initialSurah,
        initialAyahFrom: initialAyahFrom,
        initialAyahTo: initialAyahTo,
        initialAyahCount: initialAyahCount,
        totalSurahs: totalSurahs,
        onPick: (target) => Navigator.of(ctx).pop(target),
      ),
    );
  }

  @override
  State<MushafJumpSheet> createState() => _MushafJumpSheetState();
}

class _MushafJumpSheetState extends State<MushafJumpSheet> {
  late int _surah = widget.initialSurah;
  late int _count = widget.initialAyahCount < 1 ? 1 : widget.initialAyahCount;
  late int _from = widget.initialAyahFrom;
  late int _to = widget.initialAyahTo;
  bool _loadingCount = false;

  @override
  void initState() {
    super.initState();
    _clampRange();
  }

  void _clampRange() {
    final max = _count < 1 ? 1 : _count;
    _from = _from.clamp(1, max);
    _to = _to.clamp(_from, max);
  }

  /// Resolves the real ayah count for [surah] so the range pickers stay valid.
  Future<void> _loadCount(int surah) async {
    setState(() => _loadingCount = true);
    var count = 1;
    try {
      final ayahs = await LocalCorpusRepository().getAyahs(surah);
      if (ayahs.isNotEmpty) count = ayahs.length;
    } catch (_) {
      // A missing corpus entry must not block jumping; fall back to 1 ayah.
      count = 1;
    }
    if (!mounted) return;
    setState(() {
      _count = count;
      _loadingCount = false;
      // Keep the old range where it is still valid, else collapse to the whole
      // surah - never leave "from 5" pointing at a 3-ayah surah.
      final max = _count < 1 ? 1 : _count;
      if (_from > max || _to > max) {
        _from = 1;
        _to = max;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final name = surahNameArabic(_surah);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: t.text.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Jump to a verse',
            style: TextStyle(
              color: t.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'انتقل إلى سورة',
            style:
                TextStyle(color: t.text.withValues(alpha: 0.55), fontSize: 13),
          ),
          const SizedBox(height: 16),
          _MushafNumberField(
            label: 'Surah',
            value: _surah,
            count: widget.totalSurahs,
            theme: t,
            onChanged: (v) {
              setState(() => _surah = v);
              _loadCount(v);
            },
          ),
          if (name != null) ...[
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.accent, fontSize: 22, height: 1.6),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MushafNumberField(
                  label: 'From ayah',
                  value: _from,
                  count: _count,
                  theme: t,
                  onChanged: (v) => setState(() {
                    _from = v;
                    if (_to < v) _to = v;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('→', style: TextStyle(color: t.text, fontSize: 18)),
              ),
              Expanded(
                child: _MushafNumberField(
                  label: 'To ayah',
                  value: _to,
                  count: _count,
                  theme: t,
                  onChanged: (v) => setState(() {
                    _to = v < _from ? _from : v;
                  }),
                ),
              ),
            ],
          ),
          if (_loadingCount) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.accent),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading ayah count...',
                  style: TextStyle(
                      color: t.text.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => widget.onPick?.call(
              MushafJumpTarget(surah: _surah, ayahFrom: _from, ayahTo: _to),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: t.accent,
              foregroundColor:
                  t.isDark ? const Color(0xFF1A1409) : Colors.white,
            ),
            child: const Text('Jump here'),
          ),
        ],
      ),
    );
  }
}

/// A themed number picker styled like the rest of the Mushaf page.
class _MushafNumberField extends StatelessWidget {
  const _MushafNumberField({
    required this.label,
    required this.value,
    required this.count,
    required this.theme,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int count;
  final MushafTheme theme;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final max = count < 1 ? 1 : count;
    final safe = value.clamp(1, max);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.text.withValues(alpha: 0.6)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: t.accent, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: safe,
          dropdownColor: t.background,
          style: TextStyle(color: t.text, fontSize: 15),
          items: [
            for (var i = 1; i <= max; i++)
              DropdownMenuItem(value: i, child: Text('$i')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
