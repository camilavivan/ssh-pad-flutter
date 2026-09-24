import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/session/file_backend.dart';
import '../../core/session/file_browser_session.dart';
import '../../core/session/session_backend.dart';
import '../../core/session/session_manager.dart';
import '../../data/host_profile.dart';

/// Remote file browser for SFTP / FTP (list, mkdir, delete, upload, download).
class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key, this.sessionId, this.embedded = false});

  final String? sessionId;
  final bool embedded;

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  List<RemoteFileEntry> _entries = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  FileBrowserSession? get _session {
    final mgr = ref.read(sessionManagerProvider);
    final id = widget.sessionId ?? mgr.activeFileId;
    if (id == null) return mgr.activeFile;
    for (final s in mgr.files) {
      if (s.id == id) return s;
    }
    return mgr.activeFile;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final session = _session;
    if (session == null) {
      setState(() {
        _loading = false;
        _error = '无文件会话';
      });
      return;
    }
    if (session.phase == SessionPhase.connecting) {
      setState(() {
        _loading = true;
        _error = null;
      });
      // Wait briefly for connect to finish.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (session.phase == SessionPhase.error) {
      setState(() {
        _loading = false;
        _error = session.errorMessage ?? '连接失败';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await session.backend.list();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _mkdir() async {
    final name = await _prompt('新建文件夹', '名称');
    if (name == null || name.isEmpty) return;
    await _run(() => _session!.backend.mkdir(name));
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    final bytes = f.bytes;
    if (bytes == null) {
      _snack('无法读取所选文件');
      return;
    }
    await _run(() => _session!.backend.upload(f.name, bytes));
  }

  Future<void> _download(RemoteFileEntry entry) async {
    await _run(() async {
      final bytes = await _session!.backend.download(entry.name);
      final dir = await _downloadDir();
      final out = File('${dir.path}/${entry.name}');
      await out.writeAsBytes(bytes, flush: true);
      if (mounted) {
        _snack('已保存到 ${out.path}');
      }
    });
  }

  Future<Directory> _downloadDir() async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/SSHPad');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _delete(RemoteFileEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除 ${entry.name}？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _session!.backend.delete(entry));
  }

  Future<void> _openDir(RemoteFileEntry entry) async {
    await _run(() => _session!.backend.changeDirectory(entry.name));
  }

  Future<void> _goUp() async {
    await _run(() => _session!.backend.changeDirectory('..'));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _session == null) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (e) {
      if (mounted) _snack('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _prompt(String title, String label) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _close() async {
    final s = _session;
    if (s != null) {
      await ref.read(sessionManagerProvider).closeFile(s.id);
    }
    if (mounted && !widget.embedded) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionManagerProvider);
    final session = _session;
    final cleartext = session?.profile.protocol == HostProtocol.ftp &&
        session?.profile.ftpSecure == FtpSecureMode.none;

    final actions = <Widget>[
      IconButton(
        tooltip: '上级目录',
        onPressed: _busy ? null : _goUp,
        icon: const Icon(Icons.arrow_upward),
      ),
      IconButton(
        tooltip: '刷新',
        onPressed: _busy ? null : _reload,
        icon: const Icon(Icons.refresh),
      ),
      IconButton(
        tooltip: '新建文件夹',
        onPressed: _busy ? null : _mkdir,
        icon: const Icon(Icons.create_new_folder_outlined),
      ),
      IconButton(
        tooltip: '上传',
        onPressed: _busy ? null : _upload,
        icon: const Icon(Icons.upload_file),
      ),
      IconButton(
        tooltip: '断开',
        onPressed: _close,
        icon: const Icon(Icons.link_off),
      ),
    ];

    final body = Column(
      children: [
        if (cleartext)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '警告：明文 FTP。生产环境请使用 FTPS / FTPES / SFTP。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                session?.backend.currentPath ?? '',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
        ),
        if (_busy || _loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _entries.isEmpty && !_loading
              ? const Center(child: Text('空目录'))
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    return ListTile(
                      leading: Icon(
                        e.isDirectory
                            ? Icons.folder
                            : Icons.insert_drive_file_outlined,
                      ),
                      title: Text(e.name),
                      subtitle: Text(
                        e.isDirectory ? '目录' : _formatSize(e.size),
                      ),
                      onTap: e.isDirectory ? () => _openDir(e) : null,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'download' && !e.isDirectory) {
                            _download(e);
                          } else if (v == 'delete') {
                            _delete(e);
                          }
                        },
                        itemBuilder: (_) => [
                          if (!e.isDirectory)
                            const PopupMenuItem(
                              value: 'download',
                              child: Text('下载'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      session?.keepAliveTitle ?? '文件',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.keepAliveTitle ?? '文件'),
        actions: actions,
      ),
      body: body,
    );
  }

  String _formatSize(int? size) {
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Helper to open a file session then push [FilesPage].
Future<void> openFileBrowser(
  BuildContext context,
  WidgetRef ref,
  HostProfile profile,
) async {
  final mgr = ref.read(sessionManagerProvider);
  // Navigate first so connecting state is visible.
  final nav = Navigator.of(context);
  final future = mgr.openFiles(profile);
  await nav.push(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/files'),
      builder: (_) => const FilesPage(),
    ),
  );
  // When user pops, ensure we awaited connect (errors already recorded).
  await future;
}
