import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_simple/backup/backup_crypto.dart';

typedef PinHasher = Future<Uint8List> Function(String pin, Uint8List salt);

/// App PIN: only an Argon2id hash and its salt are stored, never the PIN.
/// Failed attempts survive restarts so killing the app does not reset the wait.
// ponytail: hash lives in SharedPreferences (app sandbox, excluded from
// system backup); wrap it with Android Keystore if the threat model grows to
// rooted devices.
class AppLock {
  AppLock(this.prefs,
      {PinHasher? hasher, DateTime Function()? clock})
      : hasher = hasher ?? BackupCrypto.deriveInIsolate,
        clock = clock ?? DateTime.now;

  final SharedPreferences prefs;
  final PinHasher hasher;
  final DateTime Function() clock;

  static const _hashKey = 'lockPinHash';
  static const _saltKey = 'lockPinSalt';
  static const _failsKey = 'lockFailedAttempts';
  static const _blockedKey = 'lockBlockedUntil';
  static const biometricKey = 'lockBiometric';
  static const timeoutKey = 'lockTimeoutSeconds';
  static const freeAttempts = 5;

  bool get enabled => prefs.getString(_hashKey) != null;
  bool get biometric => enabled && (prefs.getBool(biometricKey) ?? false);
  Duration get timeout => Duration(seconds: prefs.getInt(timeoutKey) ?? 0);

  static bool validPin(String pin) => RegExp(r'^\d{6,8}$').hasMatch(pin);

  Future<void> setPin(String pin) async {
    if (!validPin(pin)) throw ArgumentError('El PIN debe tener 6–8 dígitos.');
    final random = Random.secure();
    final salt =
        Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    final hash = await hasher(pin, salt);
    await prefs.setString(_saltKey, base64.encode(salt));
    await prefs.setString(_hashKey, base64.encode(hash));
    await _resetFailures();
  }

  /// Time left before another attempt is allowed, or null.
  Duration? get blockedFor {
    final until = prefs.getInt(_blockedKey);
    if (until == null) return null;
    final left =
        DateTime.fromMillisecondsSinceEpoch(until).difference(clock());
    return left.isNegative || left == Duration.zero ? null : left;
  }

  /// False for a wrong PIN or while blocked (the PIN is not even checked).
  Future<bool> verify(String pin) async {
    if (!enabled || blockedFor != null || !validPin(pin)) {
      if (enabled && blockedFor == null) await _fail();
      return false;
    }
    final salt = base64.decode(prefs.getString(_saltKey)!);
    final expected = base64.decode(prefs.getString(_hashKey)!);
    final actual = await hasher(pin, Uint8List.fromList(salt));
    var diff = expected.length ^ actual.length;
    for (var i = 0; i < min(expected.length, actual.length); i++) {
      diff |= expected[i] ^ actual[i];
    }
    if (diff != 0) {
      await _fail();
      return false;
    }
    await _resetFailures();
    return true;
  }

  Future<void> disable() async {
    for (final key in [_hashKey, _saltKey, _failsKey, _blockedKey, biometricKey]) {
      await prefs.remove(key);
    }
  }

  Future<void> _fail() async {
    final fails = (prefs.getInt(_failsKey) ?? 0) + 1;
    await prefs.setInt(_failsKey, fails);
    if (fails >= freeAttempts) {
      // 30 s, 1 min, 2 min... capped at one hour.
      final seconds = min(30 << min(fails - freeAttempts, 7), 3600);
      await prefs.setInt(_blockedKey,
          clock().add(Duration(seconds: seconds)).millisecondsSinceEpoch);
    }
  }

  Future<void> _resetFailures() async {
    await prefs.remove(_failsKey);
    await prefs.remove(_blockedKey);
  }
}

/// Our own system sheets (biometric prompt, document pickers) pause the
/// activity; that is not the user leaving the app, so it must not relock.
// ponytail: leaving the app *from* one of those sheets is not detected; it
// locks on the next real pause.
int _ownSheets = 0;
bool get ownSheetOpen => _ownSheets > 0;
Future<T> withOwnSheet<T>(Future<T> Function() action) async {
  _ownSheets++;
  try {
    return await action();
  } finally {
    _ownSheets--;
  }
}
