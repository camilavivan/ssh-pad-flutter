import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// Create an xterm [Terminal] with the correct keytab platform for this host.
Terminal createPadTerminal({int maxLines = 10000}) {
  return Terminal(
    maxLines: maxLines,
    platform: hostTerminalPlatform,
  );
}

TerminalTargetPlatform get hostTerminalPlatform {
  if (kIsWeb) return TerminalTargetPlatform.web;
  if (Platform.isAndroid) return TerminalTargetPlatform.android;
  if (Platform.isIOS) return TerminalTargetPlatform.ios;
  if (Platform.isMacOS) return TerminalTargetPlatform.macos;
  if (Platform.isLinux) return TerminalTargetPlatform.linux;
  if (Platform.isWindows) return TerminalTargetPlatform.windows;
  if (Platform.isFuchsia) return TerminalTargetPlatform.fuchsia;
  return TerminalTargetPlatform.unknown;
}
