import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/core/session/session_backend.dart';
import 'package:ssh_pad_flutter/core/session/ssh_terminal_session.dart';
import 'package:ssh_pad_flutter/core/ssh/ssh_connection_hub.dart';
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
      hub: SshConnectionHub(),
    );
    expect(s.title, '10.0.0.1');
    expect(s.phase, SessionPhase.connecting);
    expect(s.keepAliveTitle, 'SSH 10.0.0.1');
  });

  test('SshTerminalSession named title', () {
    final s = SshTerminalSession(
      id: 't2',
      profile: HostProfile(
        id: 'h2',
        name: 'lab',
        host: '10.0.0.2',
      ),
      hub: SshConnectionHub(),
    );
    expect(s.title, 'lab');
  });

  test('HostProtocol defaults and MVP flags', () {
    expect(HostProtocol.ssh.defaultPort, 22);
    expect(HostProtocol.sftp.defaultPort, 22);
    expect(HostProtocol.telnet.defaultPort, 23);
    expect(HostProtocol.ftp.defaultPort, 21);
    expect(HostProtocol.ssh.isMvp, isTrue);
    expect(HostProtocol.sftp.isMvp, isTrue);
    expect(HostProtocol.telnet.isMvp, isTrue);
    expect(HostProtocol.ftp.isMvp, isTrue);
    expect(HostProtocol.serial.isDeferred, isTrue);
    expect(HostProtocol.ftp.isFile, isTrue);
    expect(HostProtocol.telnet.isTerminal, isTrue);
  });

  test('HostProfile ftpPassive default and asSftp', () {
    final p = HostProfile(
      id: '1',
      name: 'demo',
      protocol: HostProtocol.ssh,
      host: '192.168.1.1',
      username: 'root',
      password: 'secret',
    );
    expect(p.ftpPassive, isTrue);
    final sftp = p.asSftp();
    expect(sftp.protocol, HostProtocol.sftp);
    expect(sftp.password, 'secret');
    expect(sftp.id, p.id);
    final back = HostProfile.fromJson(p.toJson());
    expect(back.ftpPassive, isTrue);
  });

  test('SshConnectionHub keys by profile id', () {
    final hub = SshConnectionHub();
    final p = HostProfile(id: 'abc', name: 'n', host: '1.2.3.4');
    expect(hub.keyFor(p), 'abc');
    expect(hub.keyFor(p.asSftp()), 'abc');
    expect(hub.isConnected('abc'), isFalse);
    expect(hub.clientOf('abc'), isNull);
  });
}
