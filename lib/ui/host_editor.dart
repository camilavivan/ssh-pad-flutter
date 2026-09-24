import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/host_profile.dart';
import '../data/host_store.dart';
import 'placeholders.dart';

class HostEditorPage extends ConsumerStatefulWidget {
  const HostEditorPage({super.key, this.existing});

  final HostProfile? existing;

  @override
  ConsumerState<HostEditorPage> createState() => _HostEditorPageState();
}

class _HostEditorPageState extends ConsumerState<HostEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late HostProtocol _protocol;
  late AuthMethod _auth;
  late FtpSecureMode _ftpSecure;
  late bool _saveSecret;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _protocol = e?.protocol ?? HostProtocol.ssh;
    _auth = e?.auth ?? AuthMethod.password;
    _ftpSecure = e?.ftpSecure ?? FtpSecureMode.none;
    _saveSecret = e?.saveSecret ?? false;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _port = TextEditingController(
      text: (e?.port ?? _protocol.defaultPort ?? 22).toString(),
    );
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController(text: e?.password ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onProtocolChanged(HostProtocol? value) {
    if (value == null) return;
    setState(() {
      _protocol = value;
      final def = value.defaultPort;
      if (def != null) {
        _port.text = def.toString();
      }
    });
  }

  Future<void> _save({bool connect = false}) async {
    final port = int.tryParse(_port.text.trim()) ??
        _protocol.defaultPort ??
        22;
    final profile = HostProfile(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
      protocol: _protocol,
      host: _host.text.trim(),
      port: port,
      username: _username.text.trim(),
      auth: _auth,
      password: _password.text.isEmpty ? null : _password.text,
      ftpSecure: _ftpSecure,
      saveSecret: _saveSecret,
    );
    await ref.read(hostListProvider.notifier).upsert(profile);
    if (!mounted) return;
    if (connect) {
      if (_protocol.isDeferred) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_protocol.label} 将在后续版本实现（稍后）')),
        );
        return;
      }
      if (_protocol == HostProtocol.sftp || _protocol == HostProtocol.ftp) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const FilesPlaceholderPage()),
        );
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TerminalPlaceholderPage(hostName: profile.name),
          ),
        );
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final deferred = _protocol.isDeferred;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '添加主机' : '编辑主机'),
        actions: [
          TextButton(
            onPressed: () => _save(connect: false),
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<HostProtocol>(
            // ignore: deprecated_member_use
            value: _protocol,
            decoration: const InputDecoration(
              labelText: '协议',
              border: OutlineInputBorder(),
            ),
            items: HostProtocol.values.map((p) {
              final label = p.isDeferred ? '${p.label}（稍后）' : p.label;
              return DropdownMenuItem(value: p, child: Text(label));
            }).toList(),
            onChanged: _onProtocolChanged,
          ),
          if (deferred) ...[
            const SizedBox(height: 8),
            Text(
              '该协议尚未实现，保存档案后可连接功能将禁用。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_protocol == HostProtocol.telnet ||
              _protocol == HostProtocol.ftp ||
              _protocol == HostProtocol.rlogin) ...[
            const SizedBox(height: 8),
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '警告：TELNET / FTP / RLOGIN 为明文凭据与会话。'
                  '生产环境请优先使用 SSH / SFTP / FTPS。',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: '主机',
              border: OutlineInputBorder(),
            ),
            enabled: _protocol != HostProtocol.local,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            decoration: const InputDecoration(
              labelText: '端口',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            enabled: _protocol.defaultPort != null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_protocol == HostProtocol.ssh ||
              _protocol == HostProtocol.sftp) ...[
            DropdownButtonFormField<AuthMethod>(
              // ignore: deprecated_member_use
              value: _auth,
              decoration: const InputDecoration(
                labelText: '认证方式',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: AuthMethod.password, child: Text('密码')),
                DropdownMenuItem(value: AuthMethod.key, child: Text('私钥')),
              ],
              onChanged: (v) => setState(() => _auth = v ?? AuthMethod.password),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _auth == AuthMethod.key ? '口令 / 私钥口令' : '密码',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_protocol == HostProtocol.ftp) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<FtpSecureMode>(
              // ignore: deprecated_member_use
              value: _ftpSecure,
              decoration: const InputDecoration(
                labelText: 'FTP 安全',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: FtpSecureMode.none, child: Text('明文 FTP')),
                DropdownMenuItem(value: FtpSecureMode.ftps, child: Text('FTPS')),
                DropdownMenuItem(value: FtpSecureMode.ftpes, child: Text('FTPES')),
              ],
              onChanged: (v) =>
                  setState(() => _ftpSecure = v ?? FtpSecureMode.none),
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('保存密钥 / 密码（本地）'),
            subtitle: const Text('后续将迁移至安全存储'),
            value: _saveSecret,
            onChanged: (v) => setState(() => _saveSecret = v),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: deferred ? null : () => _save(connect: true),
            icon: const Icon(Icons.play_arrow),
            label: Text(deferred ? '连接（稍后）' : '保存并连接'),
          ),
        ],
      ),
    );
  }
}
