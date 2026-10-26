import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Portable encrypted backups. Only this bounded, versioned format is accepted.
/// The password is never persisted here; Android protects AutoBackup material.
class BackupCrypto {
  static const maxFileBytes = 20 * 1024 * 1024;
  static const maxPlainBytes = 14 * 1024 * 1024;
  static const _format = 'allowance-privacy-encrypted';
  static const _memory = 19456;
  static const _iterations = 2;
  static const _parallelism = 1;

  static Future<Uint8List> encrypt(Uint8List plain, String password) async {
    _checkExportPassword(password);
    _checkPlain(plain);
    return Isolate.run(() async {
      final salt = _random(16);
      final key = await _derive(password, salt);
      try {
        return await _encrypt(plain, key, salt);
      } finally {
        key.fillRange(0, key.length, 0);
      }
    });
  }

  static Future<Uint8List> decrypt(Uint8List file, String password) async {
    if (file.length > maxFileBytes || password.length > 1024) {
      throw const FormatException('Copia no válida o contraseña incorrecta.');
    }
    // Reject hostile KDF parameters before reserving Argon2's memory.
    final envelope = _parse(file);
    return Isolate.run(() async {
      final salt = _decode(envelope['kdf']['salt'], 16);
      final key = await _derive(password, salt);
      try {
        final box = SecretBox(
          _decode(envelope['ciphertext'], null),
          nonce: _decode(envelope['nonce'], 12),
          mac: Mac(_decode(envelope['tag'], 16)),
        );
        final plain = await AesGcm.with256bits().decrypt(
          box,
          secretKey: SecretKey(key),
          aad: _aad(salt),
        );
        if (plain.length > maxPlainBytes) {
          throw const FormatException('Copia demasiado grande.');
        }
        return Uint8List.fromList(plain);
      } on SecretBoxAuthenticationError {
        // Do not expose decrypted partial data or distinguish password failures.
        throw const FormatException('Copia no válida o contraseña incorrecta.');
      } finally {
        key.fillRange(0, key.length, 0);
      }
    });
  }

  static Future<Map<String, Uint8List>> createMaterial(String password) async {
    _checkExportPassword(password);
    return Isolate.run(() async {
      final salt = _random(16);
      return {'key': await _derive(password, salt), 'salt': salt};
    });
  }

  /// Deterministic entry point used for interop verification, not password storage.
  static Future<Uint8List> deriveKey(String password, Uint8List salt) async {
    if (password.length > 1024 || salt.length != 16) {
      throw ArgumentError('Parámetros de derivación no válidos.');
    }
    return Isolate.run(() => _derive(password, salt));
  }

  static Future<Uint8List> encryptWithMaterial(
      Uint8List plain, Uint8List key, Uint8List salt) async {
    _checkPlain(plain);
    if (key.length != 32 || salt.length != 16) {
      throw ArgumentError('Material de cifrado no válido.');
    }
    return Isolate.run(() => _encrypt(plain, key, salt));
  }

  /// Detection only: import still validates the complete envelope in [decrypt].
  static bool isEncrypted(Uint8List bytes) {
    if (bytes.length > maxFileBytes) return false;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      return json is Map && json['format'] == _format;
    } on FormatException {
      return false;
    }
  }

  static Future<Uint8List> _derive(String password, Uint8List salt) async {
    final algorithm = Argon2id(
      memory: _memory,
      iterations: _iterations,
      parallelism: _parallelism,
      hashLength: 32,
    );
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    try {
      final key = await algorithm.deriveKey(
          secretKey: SecretKey(passwordBytes), nonce: salt);
      return Uint8List.fromList(await key.extractBytes());
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
    }
  }

  static Future<Uint8List> _encrypt(
      Uint8List plain, Uint8List key, Uint8List salt) async {
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: _random(12),
      aad: _aad(salt),
    );
    return Uint8List.fromList(utf8.encode(jsonEncode({
      ..._header(salt),
      'nonce': base64.encode(box.nonce),
      'ciphertext': base64.encode(box.cipherText),
      'tag': base64.encode(box.mac.bytes),
    })));
  }

  static Map<String, dynamic> _header(Uint8List salt) => {
        'format': _format,
        'version': 1,
        'kdf': {
          'name': 'argon2id',
          'memory': _memory,
          'iterations': _iterations,
          'parallelism': _parallelism,
          'salt': base64.encode(salt),
        },
        'cipher': 'AES-256-GCM',
      };

  static List<int> _aad(Uint8List salt) =>
      utf8.encode(jsonEncode(_header(salt)));

  static Map<String, dynamic> _parse(Uint8List bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic> ||
          !_keys(value, {
            'format',
            'version',
            'kdf',
            'cipher',
            'nonce',
            'ciphertext',
            'tag'
          }) ||
          value['format'] != _format ||
          value['version'] is! int ||
          value['version'] != 1 ||
          value['cipher'] != 'AES-256-GCM') {
        throw const FormatException('Cabecera de copia no válida.');
      }
      final kdf = value['kdf'];
      if (kdf is! Map<String, dynamic> ||
          !_keys(
              kdf, {'name', 'memory', 'iterations', 'parallelism', 'salt'}) ||
          kdf['name'] != 'argon2id' ||
          kdf['memory'] is! int ||
          kdf['memory'] != _memory ||
          kdf['iterations'] is! int ||
          kdf['iterations'] != _iterations ||
          kdf['parallelism'] is! int ||
          kdf['parallelism'] != _parallelism) {
        throw const FormatException('Derivación no compatible.');
      }
      _decode(kdf['salt'], 16);
      _decode(value['nonce'], 12);
      _decode(value['tag'], 16);
      final ciphertext = _decode(value['ciphertext'], null);
      if (ciphertext.length > maxPlainBytes) {
        throw const FormatException('Copia demasiado grande.');
      }
      return value;
    } on FormatException {
      throw const FormatException('Copia no válida o contraseña incorrecta.');
    }
  }

  static bool _keys(Map<String, dynamic> map, Set<String> keys) =>
      map.length == keys.length && keys.every(map.containsKey);

  static Uint8List _decode(dynamic value, int? length) {
    if (value is! String || value.length > (maxPlainBytes * 4 ~/ 3 + 8)) {
      throw const FormatException('Campo binario no válido.');
    }
    final decoded = base64.decode(value);
    // Canonical encoding avoids alternate encodings of authenticated metadata.
    if (base64.encode(decoded) != value ||
        (length != null && decoded.length != length)) {
      throw const FormatException('Campo binario no válido.');
    }
    return decoded;
  }

  static Uint8List _random(int size) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(size, (_) => random.nextInt(256)));
  }

  static void _checkExportPassword(String password) {
    if (password.runes.length < 12 || password.length > 1024) {
      throw ArgumentError(
          'La contraseña debe tener entre 12 y 1024 caracteres.');
    }
  }

  static void _checkPlain(Uint8List plain) {
    if (plain.length > maxPlainBytes) {
      throw ArgumentError('La copia supera el límite de 14 MiB.');
    }
  }
}
