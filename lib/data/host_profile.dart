/// Host connection profile (PadSSH / ServerBox-aligned fields for M0).
library;

enum HostProtocol {
  ssh,
  sftp,
  telnet,
  ftp,
  serial,
  local,
  rlogin;

  /// Protocols implemented in MVP (connect enabled).
  bool get isMvp =>
      this == HostProtocol.ssh ||
      this == HostProtocol.sftp ||
      this == HostProtocol.telnet ||
      this == HostProtocol.ftp;

  /// Deferred P2 protocols (show 「稍后」, disable connect).
  bool get isDeferred => !isMvp;

  String get label {
    switch (this) {
      case HostProtocol.ssh:
        return 'SSH';
      case HostProtocol.sftp:
        return 'SFTP';
      case HostProtocol.telnet:
        return 'TELNET';
      case HostProtocol.ftp:
        return 'FTP';
      case HostProtocol.serial:
        return 'SERIAL';
      case HostProtocol.local:
        return 'LOCAL';
      case HostProtocol.rlogin:
        return 'RLOGIN';
    }
  }

  int? get defaultPort {
    switch (this) {
      case HostProtocol.ssh:
      case HostProtocol.sftp:
        return 22;
      case HostProtocol.telnet:
        return 23;
      case HostProtocol.ftp:
        return 21;
      case HostProtocol.rlogin:
        return 513;
      case HostProtocol.serial:
      case HostProtocol.local:
        return null;
    }
  }

  static HostProtocol fromName(String name) {
    return HostProtocol.values.firstWhere(
      (e) => e.name == name,
      orElse: () => HostProtocol.ssh,
    );
  }
}

enum AuthMethod { password, key }

enum FtpSecureMode { none, ftps, ftpes }

class HostProfile {
  HostProfile({
    required this.id,
    required this.name,
    this.protocol = HostProtocol.ssh,
    this.host = '',
    int? port,
    this.username = '',
    this.auth = AuthMethod.password,
    this.password,
    this.privateKey,
    this.passphrase,
    this.ftpSecure = FtpSecureMode.none,
    this.serialDeviceId,
    this.baudRate,
    this.saveSecret = false,
  }) : port = port ?? protocol.defaultPort ?? 22;

  final String id;
  final String name;
  final HostProtocol protocol;
  final String host;
  final int port;
  final String username;
  final AuthMethod auth;
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final FtpSecureMode ftpSecure;
  final String? serialDeviceId;
  final int? baudRate;
  final bool saveSecret;

  HostProfile copyWith({
    String? id,
    String? name,
    HostProtocol? protocol,
    String? host,
    int? port,
    String? username,
    AuthMethod? auth,
    String? password,
    String? privateKey,
    String? passphrase,
    FtpSecureMode? ftpSecure,
    String? serialDeviceId,
    int? baudRate,
    bool? saveSecret,
  }) {
    return HostProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      auth: auth ?? this.auth,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      ftpSecure: ftpSecure ?? this.ftpSecure,
      serialDeviceId: serialDeviceId ?? this.serialDeviceId,
      baudRate: baudRate ?? this.baudRate,
      saveSecret: saveSecret ?? this.saveSecret,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'host': host,
        'port': port,
        'username': username,
        'auth': auth.name,
        if (password != null) 'password': password,
        if (privateKey != null) 'privateKey': privateKey,
        if (passphrase != null) 'passphrase': passphrase,
        'ftpSecure': ftpSecure.name,
        if (serialDeviceId != null) 'serialDeviceId': serialDeviceId,
        if (baudRate != null) 'baudRate': baudRate,
        'saveSecret': saveSecret,
      };

  factory HostProfile.fromJson(Map<String, dynamic> json) {
    final protocol = HostProtocol.fromName(json['protocol'] as String? ?? 'ssh');
    return HostProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      protocol: protocol,
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? protocol.defaultPort ?? 22,
      username: json['username'] as String? ?? '',
      auth: AuthMethod.values.firstWhere(
        (e) => e.name == (json['auth'] as String? ?? 'password'),
        orElse: () => AuthMethod.password,
      ),
      password: json['password'] as String?,
      privateKey: json['privateKey'] as String?,
      passphrase: json['passphrase'] as String?,
      ftpSecure: FtpSecureMode.values.firstWhere(
        (e) => e.name == (json['ftpSecure'] as String? ?? 'none'),
        orElse: () => FtpSecureMode.none,
      ),
      serialDeviceId: json['serialDeviceId'] as String?,
      baudRate: (json['baudRate'] as num?)?.toInt(),
      saveSecret: json['saveSecret'] as bool? ?? false,
    );
  }
}
