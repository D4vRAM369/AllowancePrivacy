import 'dart:convert';
import 'dart:typed_data';

import 'package:budget_simple/backup/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));
Uint8List edit(Uint8List file, void Function(Map<String, dynamic>) change) {
  final json = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
  change(json);
  return bytes(jsonEncode(json));
}

void main() {
  const password = 'correct horse battery staple';
  late Uint8List encrypted;

  setUpAll(() async {
    encrypted =
        await BackupCrypto.encrypt(bytes('{"budget":123.45}'), password);
  });

  test('Argon2id matches independent libargon2 1.3 fixture', () async {
    // Generated with system libargon2 argon2id_hash_raw, not this Dart package.
    final key = await BackupCrypto.deriveKey(
        password, Uint8List.fromList(List.generate(16, (i) => i)));
    expect(key.map((i) => i.toRadixString(16).padLeft(2, '0')).join(),
        '818259b6310026a8e0dbac5d2e6927abcfdb07b32258fac4f61b18b80f929085');
  });

  test('decrypts independently encrypted Python AESGCM fixture', () async {
    // Ciphertext/tag produced by Python cryptography AESGCM using the fixture key.
    final file = bytes(jsonEncode({
      'format': 'allowance-privacy-encrypted',
      'version': 1,
      'kdf': {
        'name': 'argon2id',
        'memory': 19456,
        'iterations': 2,
        'parallelism': 1,
        'salt': 'AAECAwQFBgcICQoLDA0ODw=='
      },
      'cipher': 'AES-256-GCM',
      'nonce': 'AAECAwQFBgcICQoL',
      'ciphertext': 'pJe7ePlgM0/mPT0lNw7GuSwt',
      'tag': 'sHzKIl4rV/sLpuKdNkH14A=='
    }));
    expect(utf8.decode(await BackupCrypto.decrypt(file, password)),
        '{"test":"interop"}');
  });

  test('round trip and detection', () async {
    expect(BackupCrypto.isEncrypted(encrypted), isTrue);
    expect(BackupCrypto.isEncrypted(bytes('{"version":1}')), isFalse);
    expect(BackupCrypto.isEncrypted(bytes('garbage')), isFalse);
    expect(utf8.decode(await BackupCrypto.decrypt(encrypted, password)),
        '{"budget":123.45}');
  });

  test('rejects wrong password without leaking content', () async {
    await expectLater(BackupCrypto.decrypt(encrypted, 'wrong'),
        throwsA(isA<FormatException>()));
  });

  test('rejects ciphertext, tag and nonce alterations', () async {
    for (final field in ['ciphertext', 'tag', 'nonce']) {
      final modified = edit(encrypted, (json) {
        final data = base64.decode(json[field] as String);
        data[0] ^= 1;
        json[field] = base64.encode(data);
      });
      await expectLater(BackupCrypto.decrypt(modified, password),
          throwsA(isA<FormatException>()));
    }
  });

  test('rejects modified headers and unreasonable KDF before deriving',
      () async {
    for (final change in <void Function(Map<String, dynamic>)>[
      (j) => j['version'] = 2,
      (j) => j['cipher'] = 'AES-CBC',
      (j) => (j['kdf'] as Map)['memory'] = 2147483647,
      (j) => (j['kdf'] as Map)['iterations'] = 0,
      (j) => (j['kdf'] as Map)['parallelism'] = 2,
      (j) => j['untrusted'] = 'extra',
      (j) => j['tag'] = '',
      (j) => j['nonce'] = '!',
    ]) {
      await expectLater(BackupCrypto.decrypt(edit(encrypted, change), password),
          throwsA(isA<FormatException>()));
    }
  });

  test('fresh nonces under the same stored autobackup key', () async {
    final material = await BackupCrypto.createMaterial(password);
    final first = await BackupCrypto.encryptWithMaterial(
        bytes('same'), material['key']!, material['salt']!);
    final second = await BackupCrypto.encryptWithMaterial(
        bytes('same'), material['key']!, material['salt']!);
    expect(jsonDecode(utf8.decode(first))['nonce'],
        isNot(jsonDecode(utf8.decode(second))['nonce']));
    expect(await BackupCrypto.decrypt(second, password), bytes('same'));
  });

  test('Unicode passwords and export password rules', () async {
    const unicode = 'Contraseña larga 🔐 العربية';
    final file = await BackupCrypto.encrypt(bytes('áéí €'), unicode);
    expect(await BackupCrypto.decrypt(file, unicode), bytes('áéí €'));
    await expectLater(
        BackupCrypto.encrypt(bytes('x'), 'short'), throwsArgumentError);
    await expectLater(
        BackupCrypto.createMaterial('x' * 1025), throwsArgumentError);
    await expectLater(
        BackupCrypto.deriveKey(password, Uint8List(2)), throwsArgumentError);
  });

  test('bounds and truncated data fail closed', () async {
    await expectLater(BackupCrypto.decrypt(bytes('{'), password),
        throwsA(isA<FormatException>()));
    await expectLater(
        BackupCrypto.decrypt(Uint8List(20 * 1024 * 1024 + 1), password),
        throwsA(isA<FormatException>()));
    await expectLater(
        BackupCrypto.encrypt(Uint8List(14 * 1024 * 1024 + 1), password),
        throwsArgumentError);
  });
}
