import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../data/host_profile.dart';
import '../session/file_backend.dart';

/// SFTP via dartssh2 [SftpClient]. Auth matches SSH [HostProfile].
class SftpFileBackend implements FileBackend {
  SftpFileBackend(this.profile);

  final HostProfile profile;
  SSHClient? _client;
  SftpClient? _sftp;
  String _cwd = '.';

  @override
  String get currentPath => _cwd;

  @override
  Future<void> connect() async {
    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: const Duration(seconds: 20),
    );

    List<SSHKeyPair>? identities;
    if (profile.auth == AuthMethod.key) {
      final pem = profile.privateKey?.trim();
      if (pem == null || pem.isEmpty) {
        throw StateError('Private key is empty');
      }
      identities = SSHKeyPair.fromPem(pem, profile.passphrase);
    }

    final client = SSHClient(
      socket,
      username: profile.username.isEmpty ? 'root' : profile.username,
      identities: identities,
      onPasswordRequest: profile.auth == AuthMethod.password
          ? () => profile.password ?? ''
          : (profile.passphrase != null && profile.passphrase!.isNotEmpty
              ? () => profile.passphrase!
              : null),
      keepAliveInterval: const Duration(seconds: 8),
      onVerifyHostKey: (type, key) => true,
    );
    _client = client;
    await client.authenticated;
    _sftp = await client.sftp();
    try {
      _cwd = await _sftp!.absolute('.');
    } catch (_) {
      _cwd = '/';
    }
  }

  @override
  Future<List<RemoteFileEntry>> list([String? path]) async {
    final sftp = _sftp;
    if (sftp == null) throw StateError('SFTP not connected');
    final target = path ?? _cwd;
    final names = await sftp.listdir(target);
    final entries = <RemoteFileEntry>[];
    for (final n in names) {
      if (n.filename == '.' || n.filename == '..') continue;
      entries.add(
        RemoteFileEntry(
          name: n.filename,
          isDirectory: n.attr.isDirectory,
          size: n.attr.size,
          modified: n.attr.modifyTime != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  n.attr.modifyTime! * 1000,
                )
              : null,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (path != null) _cwd = path;
    return entries;
  }

  @override
  Future<void> changeDirectory(String path) async {
    final sftp = _sftp;
    if (sftp == null) throw StateError('SFTP not connected');
    String next;
    if (path == '..') {
      final abs = await sftp.absolute(_cwd);
      final idx = abs.lastIndexOf('/');
      next = idx <= 0 ? '/' : abs.substring(0, idx);
      if (next.isEmpty) next = '/';
    } else if (path.startsWith('/')) {
      next = path;
    } else {
      next = _cwd.endsWith('/') ? '$_cwd$path' : '$_cwd/$path';
    }
    final st = await sftp.stat(next);
    if (!st.isDirectory) {
      throw StateError('Not a directory: $next');
    }
    _cwd = await sftp.absolute(next);
  }

  @override
  Future<void> mkdir(String name) async {
    final sftp = _sftp;
    if (sftp == null) throw StateError('SFTP not connected');
    final path = _cwd.endsWith('/') ? '$_cwd$name' : '$_cwd/$name';
    await sftp.mkdir(path);
  }

  @override
  Future<void> delete(RemoteFileEntry entry) async {
    final sftp = _sftp;
    if (sftp == null) throw StateError('SFTP not connected');
    final path =
        _cwd.endsWith('/') ? '$_cwd${entry.name}' : '$_cwd/${entry.name}';
    if (entry.isDirectory) {
      await sftp.rmdir(path);
    } else {
      await sftp.remove(path);
    }
  }

  @override
  Future<void> upload(String remoteName, Uint8List bytes) async {
    final sftp = _sftp;
    if (sftp == null) throw StateError('SFTP not connected');
    final path =
        _cwd.endsWith('/') ? '$_cwd$remoteName' : '$_cwd/$remoteName';
    final file = await sftp.open(
      path,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.writeBytes(bytes);
    } finally {
      await file.close();
    }
  }

  @override
  Future<Uint8List> download(String remoteName) async {
    final sftp = _sftp;
    if (sftp == null) throw StateError('SFTP not connected');
    final path =
        _cwd.endsWith('/') ? '$_cwd$remoteName' : '$_cwd/$remoteName';
    final file = await sftp.open(path, mode: SftpFileOpenMode.read);
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.read()) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      _sftp = null;
      _client?.close();
    } catch (_) {}
    _client = null;
  }
}
