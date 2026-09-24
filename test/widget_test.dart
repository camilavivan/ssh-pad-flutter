import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/data/host_profile.dart';

void main() {
  test('HostProtocol default ports', () {
    expect(HostProtocol.ssh.defaultPort, 22);
    expect(HostProtocol.sftp.defaultPort, 22);
    expect(HostProtocol.telnet.defaultPort, 23);
    expect(HostProtocol.ftp.defaultPort, 21);
    expect(HostProtocol.rlogin.defaultPort, 513);
    expect(HostProtocol.serial.isDeferred, isTrue);
    expect(HostProtocol.local.isDeferred, isTrue);
    expect(HostProtocol.ssh.isMvp, isTrue);
  });

  test('HostProfile json roundtrip', () {
    final p = HostProfile(
      id: '1',
      name: 'demo',
      protocol: HostProtocol.telnet,
      host: '192.168.1.1',
      username: 'root',
    );
    final back = HostProfile.fromJson(p.toJson());
    expect(back.protocol, HostProtocol.telnet);
    expect(back.port, 23);
    expect(back.host, '192.168.1.1');
  });
}
