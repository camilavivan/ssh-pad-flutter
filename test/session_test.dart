import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/core/session/ssh_terminal_session.dart';
import 'package:ssh_pad_flutter/data/host_profile.dart';

void main() {
  test('SshTerminalSession title falls back to host', () {
    final s = SshTerminalSession(
      id: 't1',
      profile: HostProfile(
        id: 'h1',
        name: '',
        host: '10.0.0.1',
        username: 'u',
      ),
    );
    expect(s.title, '10.0.0.1');
    expect(s.phase, SshSessionPhase.connecting);
  });

  test('SshTerminalSession named title', () {
    final s = SshTerminalSession(
      id: 't2',
      profile: HostProfile(
        id: 'h2',
        name: 'lab',
        host: '10.0.0.2',
      ),
    );
    expect(s.title, 'lab');
  });
}
