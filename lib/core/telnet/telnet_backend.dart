/// Thin SessionBackend-shaped stub for Telnet (M0).
/// Real wire-up with [ctelnet] lands in M2; M1b keepalive is independent.
abstract class TelnetBackend {
  Future<void> connect({
    required String host,
    required int port,
  });

  void write(String data);

  Stream<String> get stdout;

  Future<void> disconnect();
}

/// Placeholder until M2 — no socket yet.
class PlaceholderTelnetBackend implements TelnetBackend {
  @override
  Future<void> connect({required String host, required int port}) async {
    throw UnimplementedError('Telnet connect lands in M2');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Stream<String> get stdout => const Stream.empty();

  @override
  void write(String data) {}
}
