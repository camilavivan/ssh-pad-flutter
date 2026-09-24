
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_pad_flutter/core/security/host_key_store.dart';
import 'package:ssh_pad_flutter/core/security/host_key_verifier.dart';
import 'package:ssh_pad_flutter/data/host_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TOFU host keys', () {
    late HostKeyStore store;
    late HostKeyVerifier verifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = HostKeyStore(prefs);
      verifier = HostKeyVerifier(store);
    });

    Uint8List fp(String s) => Uint8List.fromList(utf8.encode(s));

    test('first seen auto-accepts without UI and persists', () async {
      final ok = await verifier.verify(
        host: 'example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprintBytes: fp('SHA256:abcdef'),
      );
      expect(ok, isTrue);
      final trusted = store.lookup('example.com', 22);
      expect(trusted, isNotNull);
      expect(trusted!.fingerprint, 'SHA256:abcdef');
      expect(trusted.keyType, 'ssh-ed25519');
    });

    test('matching key accepts silently', () async {
      await store.trust(
        TrustedHostKey(
          host: 'h',
          port: 22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:x',
          trustedAt: DateTime.now().toUtc(),
        ),
      );
      final ok = await verifier.verify(
        host: 'h',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprintBytes: fp('SHA256:x'),
      );
      expect(ok, isTrue);
    });

    test('mismatch without UI rejects', () async {
      await store.trust(
        TrustedHostKey(
          host: 'h',
          port: 22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:old',
          trustedAt: DateTime.now().toUtc(),
        ),
      );
      final ok = await verifier.verify(
        host: 'h',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprintBytes: fp('SHA256:new'),
      );
      expect(ok, isFalse);
    });

    test('mismatch replace updates store', () async {
      await store.trust(
        TrustedHostKey(
          host: 'h',
          port: 22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:old',
          trustedAt: DateTime.now().toUtc(),
        ),
      );
      verifier.promptHandler = (_) async => HostKeyDecision.replace;
      final ok = await verifier.verify(
        host: 'h',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprintBytes: fp('SHA256:new'),
      );
      expect(ok, isTrue);
      expect(store.lookup('h', 22)!.fingerprint, 'SHA256:new');
    });
  });

  group('HostProfile secrets metadata', () {
    test('toJson omits secrets by default', () {
      final p = HostProfile(
        id: '1',
        name: 'n',
        host: 'h',
        password: 'secret',
        privateKey: 'KEY',
        passphrase: 'pp',
        saveSecret: true,
      );
      final json = p.toJson();
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('privateKey'), isFalse);
      expect(json.containsKey('passphrase'), isFalse);
      expect(json['saveSecret'], isTrue);
      final withSecrets = p.toJson(includeSecrets: true);
      expect(withSecrets['password'], 'secret');
    });
  });
}
