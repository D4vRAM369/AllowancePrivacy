import 'package:flutter/services.dart';

/// Only the Android bridge sees document URIs and protected local keys.
class BackupPlatform {
  static const channel = MethodChannel('allowance_privacy/backup');

  Future<Uint8List?> readDocument() =>
      channel.invokeMethod<Uint8List>('readDocument');
  Future<bool> writeDocument(String name, String mime, Uint8List bytes) async =>
      await channel.invokeMethod<bool>(
          'writeDocument', {'name': name, 'mime': mime, 'bytes': bytes}) ??
      false;
  Future<bool> pickFolder() async =>
      await channel.invokeMethod<bool>('pickBackupFolder') ?? false;
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      await channel.invokeMapMethod<String, dynamic>('getAutoBackupStatus') ??
          {});
  Future<void> configure(Uint8List key, Uint8List salt,
          {required int hours, required int retention}) =>
      channel.invokeMethod('configureAutoBackup', {
        'key': key,
        'salt': salt,
        'intervalHours': hours,
        'retention': retention
      });
  Future<void> disable() => channel.invokeMethod('disableAutoBackup');
  Future<Map<String, dynamic>?> material() =>
      channel.invokeMapMethod<String, dynamic>('autoBackupMaterial');
  Future<void> writeAutomatic(Uint8List bytes, String generation) =>
      channel.invokeMethod(
          'writeAutoBackup', {'bytes': bytes, 'generation': generation});
}
