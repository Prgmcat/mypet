import 'dart:async';

import 'package:flutter/material.dart';

OverlayEntry? _activeToast;
Timer? _activeTimer;

/// Shows a brief, non-blocking toast at the bottom of the screen.
///
/// [error] only changes the icon; every message shown to the user should
/// already be localized.
void showToast(BuildContext context, String message, {bool error = false}) {
  final text = message.trim();
  if (text.isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _dismissToast();
  final entry = OverlayEntry(
    builder: (context) {
      final keyboard = MediaQuery.of(context).viewInsets.bottom;
      return Positioned(
        left: 24,
        right: 24,
        bottom: keyboard > 0 ? keyboard + 20 : 48,
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF0323232),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      error ? Icons.error_outline : Icons.check_circle_outline,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
  _activeToast = entry;
  _activeTimer = Timer(const Duration(milliseconds: 2200), _dismissToast);
}

void _dismissToast() {
  _activeTimer?.cancel();
  _activeTimer = null;
  final entry = _activeToast;
  _activeToast = null;
  try {
    entry?.remove();
  } catch (_) {
    // The overlay may already be gone with its page.
  }
}
