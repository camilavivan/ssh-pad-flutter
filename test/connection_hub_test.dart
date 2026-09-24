import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/core/sftp/sftp_file_backend.dart';
import 'package:ssh_pad_flutter/core/ssh/ssh_connection_hub.dart';
import 'package:ssh_pad_flutter/data/host_profile.dart';

void main() {
  test('SftpFileBackend constructed with hub does not own a client yet', () {
    final hub = SshConnectionHub();
    final backend = SftpFileBackend(
      HostProfile(
        id: 'h',
        name: 'lab',
        protocol: HostProtocol.sftp,
        host: '10.0.0.1',
      ),
      hub: hub,
    );
    expect(backend.currentPath, '.');
    // list before connect must fail with the known message
    expect(
      () => backend.list(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'SFTP not connected',
        ),
      ),
    );
  });

  test('asSftp preserves credentials for shared attach', () {
    final ssh = HostProfile(
      id: 'same',
      name: 'box',
      protocol: HostProtocol.ssh,
      host: '192.168.0.1',
      username: 'root',
      password: 'p@ss',
      privateKey: 'KEY',
      passphrase: 'pp',
    );
    final sftp = ssh.asSftp();
    expect(sftp.id, 'same');
    expect(sftp.password, 'p@ss');
    expect(sftp.privateKey, 'KEY');
    expect(sftp.passphrase, 'pp');
    expect(sftp.host, ssh.host);
    expect(sftp.port, ssh.port);
  });

  test('hub disconnect on unknown id is a no-op', () async {
    final hub = SshConnectionHub();
    await hub.disconnect('missing');
    await hub.disconnectAll();
    expect(hub.isConnected('missing'), isFalse);
  });
}
