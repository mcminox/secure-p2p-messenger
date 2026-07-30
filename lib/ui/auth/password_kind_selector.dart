import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../auth/secure_app_repository.dart';

class PasswordKindSelector extends StatelessWidget {
  const PasswordKindSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AppPasswordKind selected;
  final ValueChanged<AppPasswordKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 400;
        final children = [
          Expanded(
            child: _KindCard(
              title: 'Текстовый',
              subtitle: 'Буквы, цифры, символы · от 10 знаков',
              icon: Icons.text_fields_rounded,
              selected: selected == AppPasswordKind.text,
              onTap: () => onChanged(AppPasswordKind.text),
              accent: cs.primary,
            ),
          ),
          SizedBox(width: narrow ? 0 : 14, height: narrow ? 12 : 0),
          Expanded(
            child: _KindCard(
              title: 'Цифровой ПИН',
              subtitle: 'Только цифры · от 6 знаков',
              icon: Icons.dialpad_rounded,
              selected: selected == AppPasswordKind.pin,
              onTap: () => onChanged(AppPasswordKind.pin),
              accent: cs.secondary,
            ),
          ),
        ];
        return SizedBox(
          height: narrow ? 220 : 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    color: Colors.black.withValues(alpha: 0.25),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanLinePainter(
                      color: cs.secondary.withValues(alpha: 0.12),
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat()).custom(
                      duration: 4.seconds,
                      builder: (context, v, child) {
                        return ShaderMask(
                          shaderCallback: (r) => LinearGradient(
                            begin: Alignment(0, -1 + 2 * v),
                            end: Alignment(0, 0.2 + 2 * v),
                            colors: [
                              Colors.transparent,
                              cs.primary.withValues(alpha: 0.15),
                              Colors.transparent,
                            ],
                          ).createShader(r),
                          blendMode: BlendMode.srcATop,
                          child: child,
                        );
                      },
                    ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          children[0],
                          children[1],
                          children[2],
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          children[0],
                          children[1],
                          children[2],
                        ],
                      ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 1.8 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
            color: selected
                ? accent.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? accent : Colors.white54, size: 28),
              const Spacer(),
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.4,
                      color: selected ? Colors.white : Colors.white54,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                      height: 1.25,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  _ScanLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) => false;
}
