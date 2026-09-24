import 'package:flutter/material.dart';

/// Layout breakpoints aligned with Material / Kotlin ssh-pad (≥600dp split).
abstract final class PadBreakpoints {
  /// Width at or above which the pad uses a dual-pane split + drag divider.
  static const double split = 600;

  /// Minimum left pane width when dragging.
  static const double leftMin = 220;

  /// Default left pane width (dp).
  static const double leftDefault = 300;

  /// Max left fraction of total width.
  static const double leftMaxFraction = 0.45;

  /// Minimum tappable control size (ssh-pad README / Material).
  static const double minTap = 48;

  /// Floor for status-bar / cutout top guard when insets report 0 (OEM quirk).
  static const double statusBarFloor = 40;

  static bool isSplit(BoxConstraints constraints) =>
      constraints.maxWidth >= split;

  static bool isSplitSize(Size size) => size.width >= split;
}
