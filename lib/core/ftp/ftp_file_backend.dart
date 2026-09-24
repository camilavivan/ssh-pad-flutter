import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';

import '../../data/host_profile.dart';
import '../session/file_backend.dart';

/// FTP / FTPS / FTPES via [ftpconnect]. Shares [FileBackend] with SFTP.
class FtpFileBackend implements FileBackend {
  FtpFileBackend(this.profile);

  final HostProfile profile;
  FTPConnect? _ftp;
  String _cwd = '/';

  @override
  String get currentPath => _cwd;

  SecurityType get _security {
    switch (profile.ftpSecure) {
      case FtpSecureMode.ftps:
        return SecurityType.ftps;
      case FtpSecureMode.ftpes:
        return SecurityType.ftpes;
      case FtpSecureMode.none:
        return SecurityType.ftp;
    }
  }

  @override
  Future<void> connect() async {
    final ftp = FTPConnect(
      profile.host,
      port: profile.port,
      user: profile.username.isEmpty ? 'anonymous' : profile.username,
      pass: profile.password ?? '',
      securityType: _security,
      timeout: 30,
    );
    ftp.transferMode =
        profile.ftpPassive ? TransferMode.passive : TransferMode.active;
    final ok = await ftp.connect();
    if (!ok) {
      throw StateError('FTP connect failed');
    }
    _ftp = ftp;
    try {
      _cwd = await ftp.currentDirectory();
    } catch (_) {
      _cwd = '/';
    }
  }

  @override
  Future<List<RemoteFileEntry>> list([String? path]) async {
    final ftp = _ftp;
    if (ftp == null) throw StateError('FTP not connected');
    if (path != null && path != _cwd) {
      final ok = await ftp.changeDirectory(path);
      if (!ok) throw StateError('Cannot change directory to $path');
      _cwd = await ftp.currentDirectory();
    }
    final entries = await ftp.listDirectoryContent();
    final out = <RemoteFileEntry>[];
    for (final e in entries) {
      if (e.name == '.' || e.name == '..') continue;
      out.add(
        RemoteFileEntry(
          name: e.name,
          isDirectory: e.type == FTPEntryType.dir,
          size: e.size,
          modified: e.modifyTime,
        ),
      );
    }
    out.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  @override
  Future<void> changeDirectory(String path) async {
    final ftp = _ftp;
    if (ftp == null) throw StateError('FTP not connected');
    final ok = await ftp.changeDirectory(path);
    if (!ok) throw StateError('Cannot change directory to $path');
    _cwd = await ftp.currentDirectory();
  }

  @override
  Future<void> mkdir(String name) async {
    final ftp = _ftp;
    if (ftp == null) throw StateError('FTP not connected');
    final ok = await ftp.makeDirectory(name);
    if (!ok) throw StateError('mkdir failed: $name');
  }

  @override
  Future<void> delete(RemoteFileEntry entry) async {
    final ftp = _ftp;
    if (ftp == null) throw StateError('FTP not connected');
    final ok = entry.isDirectory
        ? await ftp.deleteDirectory(entry.name)
        : await ftp.deleteFile(entry.name);
    if (!ok) throw StateError('delete failed: ${entry.name}');
  }

  @override
  Future<void> upload(String remoteName, Uint8List bytes) async {
    final ftp = _ftp;
    if (ftp == null) throw StateError('FTP not connected');
    final tmp = File(
      '${Directory.systemTemp.path}/ssh_pad_up_${DateTime.now().microsecondsSinceEpoch}_$remoteName',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      final ok = await ftp.uploadFile(tmp, sRemoteName: remoteName);
      if (!ok) throw StateError('upload failed: $remoteName');
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  @override
  Future<Uint8List> download(String remoteName) async {
    final ftp = _ftp;
    if (ftp == null) throw StateError('FTP not connected');
    final tmp = File(
      '${Directory.systemTemp.path}/ssh_pad_dl_${DateTime.now().microsecondsSinceEpoch}_$remoteName',
    );
    try {
      final ok = await ftp.downloadFile(remoteName, tmp);
      if (!ok) throw StateError('download failed: $remoteName');
      return await tmp.readAsBytes();
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _ftp?.disconnect();
    } catch (_) {}
    _ftp = null;
  }
}
