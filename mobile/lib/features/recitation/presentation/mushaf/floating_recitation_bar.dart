import 'package:flutter/material.dart';

import 'mushaf_theme.dart';

/// Sleek, semi-transparent floating control bar (Tarteel style).
///
/// Replaces the old full-width "Start Reciting" card that consumed a quarter of
/// the screen. Three compact affordances only:
///   * a circular mic that pulses while listening,
///   * a quick ayah/page jump,
///   * the appearance (theme) trigger.
///
/// It is deliberately a child of the page (not a Scaffold `bottomNavigationBar`)
/// so the page can slide it away with the app bar for distraction-free reading.
class FloatingRecitationBar extends StatefulWidget {
  const FloatingRecitationBar({
    super.key,
    required this.theme,
    required this.listening,
    required this.onMicTap,
    required this.onJumpTap,
    this.onStop,
    this.stopLabel = 'Stop & Review',
    this.micLabel = 'Start reciting',
  });

  final MushafTheme theme;

  /// Drives the pulse ring and the mic icon.
  final bool listening;

  final VoidCallback onMicTap;
  final VoidCallback onJumpTap;
  final VoidCallback? onStop;
  final String stopLabel;
  final String micLabel;

  @override
  State<FloatingRecitationBar> createState() => _FloatingRecitationBarState();
}

class _FloatingRecitationBarState extends State<FloatingRecitationBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    // Only animate while listening, so an idle screen burns no frames.
    if (widget.listening) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        // Semi-transparent so the paper shows through — glassy, not a card.
        color: Color.alphaBlend(
          t.text.withValues(alpha: t.isDark ? 0.30 : 0.10),
          t.background,
        ).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: t.border.withValues(alpha: 0.7), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.45 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CircleAction(
            theme: t,
            icon: Icons.menu_book_rounded,
            tooltip: 'Jump to ayah / page',
            onTap: widget.onJumpTap,
          ),
          _MicButton(
            theme: t,
            listening: widget.listening,
            pulse: _pulse,
            label: widget.micLabel,
            onTap: widget.onMicTap,
          ),
          if (widget.onStop != null)
            _CircleAction(
              theme: t,
              icon: Icons.stop_rounded,
              tooltip: widget.stopLabel,
              emphasise: true,
              onTap: widget.onStop!,
            )
          else
            const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.theme,
    required this.listening,
    required this.pulse,
    required this.label,
    required this.onTap,
  });

  final MushafTheme theme;
  final bool listening;
  final Animation<double> pulse;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 62,
          height: 62,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              final p = listening ? pulse.value : 0.0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Expanding halo — the "waveform" indicator.
                  if (listening)
                    Transform.scale(
                      key: const ValueKey<String>('mushaf-mic-halo'),
                      scale: 1.0 + 0.42 * p,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.accent.withValues(alpha: 0.30 * (1 - p)),
                        ),
                      ),
                    ),
                  child!,
                ],
              );
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: listening ? t.accent : t.accent.withValues(alpha: 0.16),
                border: Border.all(color: t.accent, width: 1.6),
                boxShadow: [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.28),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(
                listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                color: listening
                    ? (t.isDark ? const Color(0xFF1A1409) : Colors.white)
                    : t.accent,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.theme,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.emphasise = false,
  });

  final MushafTheme theme;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: emphasise
                ? t.mismatchInk.withValues(alpha: 0.12)
                : t.text.withValues(alpha: 0.05),
            border: Border.all(
              color: emphasise
                  ? t.mismatchInk.withValues(alpha: 0.5)
                  : t.border.withValues(alpha: 0.8),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: emphasise ? t.mismatchInk : t.text.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
