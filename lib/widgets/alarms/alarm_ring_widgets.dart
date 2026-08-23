import 'dart:ui';
import 'package:flutter/material.dart';

/// Soft pulsing glow with a centered alarm glyph.
class GlowDot extends StatefulWidget {
  const GlowDot({super.key});

  @override
  State<GlowDot> createState() => _GlowDotState();
}

class _GlowDotState extends State<GlowDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF7C6CFF).withValues(alpha: 0.10 + t * 0.06),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C6CFF).withValues(alpha: 0.25 + t * 0.25),
                blurRadius: 30 + t * 20,
                spreadRadius: 2 + t * 4,
              ),
            ],
          ),
          child: Icon(
            Icons.alarm_rounded,
            size: 34,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        );
      },
    );
  }
}

/// Frosted-glass pill button — used for both Stop (filled) and Snooze
/// (unfilled), so they share the same size/shape and only differ in
/// fill/emphasis, keeping Stop read as primary without Snooze looking
/// like an afterthought.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: filled
              ? const Color(0xFF7C6CFF).withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.06),
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: filled ? 0.15 : 0.12),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
