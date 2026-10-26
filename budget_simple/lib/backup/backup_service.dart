import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_simple/database/tables.dart';
import 'backup_crypto.dart';
import 'backup_platform.dart';
import 'data_transfer.dart';

/// One logical snapshot, rather than copying a live SQLite/WAL file.
class BackupService {
  BackupService(this.db, this.preferences, {BackupPlatform? platform})
      : platform = platform ?? BackupPlatform();
  final TransactionsDatabase db;
  final SharedPreferences preferences;
  final BackupPlatform platform;
  static const preferenceKeys = [
    'currencyIcon',
    'language',
    'themeMode',
    'hapticFeedback'
  ];

  Map<String, Object> _preferences() => {
        for (final key in preferenceKeys)
          if (preferences.get(key) is String || preferences.get(key) is bool)
            key: preferences.get(key) as Object,
      };
  Future<BackupData> snapshot() async {
    final data = await DataTransfer(db).snapshot();
    return BackupData(
        transactions: data.transactions,
        budget: data.budget,
        preferences: _preferences());
  }

  Future<Uint8List> plainBackup() async =>
      Uint8List.fromList(utf8.encode(jsonEncode((await snapshot()).toJson())));
  Future<Uint8List> createBackup({String? password}) async {
    final bytes = await plainBackup();
    if (bytes.length > 14 * 1024 * 1024) {
      throw const FormatException('La copia supera el límite de 14 MB.');
    }
    if (password == null) return bytes;
    return BackupCrypto.encrypt(bytes, password);
  }

  Future<BackupData> parseBackup(Uint8List bytes, {String? password}) async {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('El archivo supera el límite de 20 MB.');
    }
    if (BackupCrypto.isEncrypted(bytes)) {
      if (password == null) {
        throw const FormatException('La copia requiere contraseña.');
      }
      bytes = await BackupCrypto.decrypt(bytes, password);
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Formato de copia no reconocido.');
    }
    return BackupData.fromJson(json);
  }

  Future<void> _applyPreferences(Map<String, Object> values) async {
    for (final key in preferenceKeys) {
      final value = values[key];
      final bool ok;
      if (value == null) {
        ok = await preferences.remove(key);
      } else if (value is bool) {
        ok = await preferences.setBool(key, value);
      } else {
        ok = await preferences.setString(key, value as String);
      }
      if (!ok) throw StateError('No se pudieron guardar los ajustes.');
    }
  }

  /// Financial writes are atomic; compensate cosmetic preferences on failure.
  Future<void> restore(BackupData data) async {
    final previous = _preferences();
    try {
      await db.transaction(() async {
        await DataTransfer(db).restore(data);
        await _applyPreferences(data.preferences);
      });
    } catch (_) {
      await _applyPreferences(previous);
      rethrow;
    }
  }

  Future<void> runAutomatic() async {
    final material = await platform.material();
    if (material == null) throw StateError('AutoBackup no está configurado.');
    await preferences.reload();
    final key = material['key'] as Uint8List;
    try {
      final plain = await plainBackup();
      final bytes = await BackupCrypto.encryptWithMaterial(
          plain, key, material['salt'] as Uint8List);
      await platform.writeAutomatic(bytes, material['generation'] as String);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}
