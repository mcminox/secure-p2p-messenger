import 'dart:ui';

import 'package:flutter/material.dart';

abstract final class AppSnack {
  static void show(BuildContext context, String message, {Duration? duration}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        duration: duration ?? const Duration(seconds: 4),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF132033).withValues(alpha: 0.55),
                border: Border.all(
                  color: const Color(0xFF4DE6D3).withValues(alpha: 0.46),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6E42E5).withValues(alpha: 0.28),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.35,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
