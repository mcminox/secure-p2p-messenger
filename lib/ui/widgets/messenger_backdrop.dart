import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class MessengerBackdrop extends StatelessWidget {
  const MessengerBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.25,
              colors: [
                cs.primary.withValues(alpha: 0.35),
                const Color(0xFF0A0D18),
                cs.secondary.withValues(alpha: 0.16),
              ],
              stops: const [0.0, 0.58, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ).animate().fade(duration: 450.ms),
        Positioned(
          right: -120,
          top: -90,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.secondary.withValues(alpha: 0.08),
            ),
          ),
        ),
        Positioned(
          left: -100,
          bottom: -120,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.1),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.15),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.35),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        child,
      ],
    );
  }
}
