import 'dart:typed_data';

/// Remote filesystem entry for SFTP / FTP list UI.
class RemoteFileEntry {
  const RemoteFileEntry({
    required this.name,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
}

/// File-transfer backends share one Files UI.
abstract class FileBackend {
  String get currentPath;

  Future<void> connect();

  Future<List<RemoteFileEntry>> list([String? path]);

  Future<void> changeDirectory(String path);

  Future<void> mkdir(String name);

  Future<void> delete(RemoteFileEntry entry);

  Future<void> upload(String remoteName, Uint8List bytes);

  /// Download remote file bytes (caller writes to device storage).
  Future<Uint8List> download(String remoteName);

  Future<void> disconnect();
}
