/// Shared session lifecycle for interactive terminal backends (SSH / Telnet).
library;

import 'dart:typed_data';

enum SessionPhase { connecting, connected, disconnected, error }

/// Wire-level terminal session (stdin / stdout / optional resize).
abstract class SessionBackend {
  Future<void> connect();

  void write(Uint8List data);

  Stream<Uint8List> get stdout;

  /// Optional PTY / NAWS resize. Default no-op.
  Future<void> resize(int cols, int rows) async {}

  Future<void> disconnect();
}
