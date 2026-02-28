import 'package:flutter/material.dart';

/// HMI color palette — industrial dark theme.
/// Locked: accent #E8763A, void #0C0C0E.
abstract class HmiColors {
  // ── Backgrounds ───────────────────────────────────────────────────
  static const Color void_ = Color(0xFF0C0C0E);
  static const Color surface = Color(0xFF18181C);
  static const Color surfaceRaised = Color(0xFF222228);
  static const Color surfaceBorder = Color(0xFF2A2A32);

  // ── Accent ────────────────────────────────────────────────────────
  static const Color accent = Color(0xFFE8763A);
  static const Color accentDim = Color(0x33E8763A); // 20% opacity

  // ── Semantic ──────────────────────────────────────────────────────
  static const Color healthy = Color(0xFF3DD68C);
  static const Color warning = Color(0xFFE8B63A);
  static const Color danger = Color(0xFFE84057);
  static const Color info = Color(0xFF5B9CF5);

  // ── Semantic Dim (for backgrounds/badges) ─────────────────────────
  static const Color healthyDim = Color(0x333DD68C);
  static const Color warningDim = Color(0x33E8B63A);
  static const Color dangerDim = Color(0x33E84057);

  // ── Text ──────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFE8E8EC);
  static const Color textSecondary = Color(0xFF8B8B96);
  static const Color textMuted = Color(0xFF55555F);

  // ── Batch State Colors ────────────────────────────────────────────
  static Color batchStateColor(String state) {
    return switch (state) {
      'IDLE' => textMuted,
      'HEATING' => danger,
      'HOLDING' => accent,
      'COOLING' => info,
      'COMPLETE' => healthy,
      _ => textMuted,
    };
  }
}
