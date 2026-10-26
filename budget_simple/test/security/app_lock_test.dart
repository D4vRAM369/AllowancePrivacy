import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_simple/security/app_lock.dart';
import 'package:budget_simple/security/lock_gate.dart';

// Fast stand-in for Argon2id; the real KDF is exercised once below.
Future<Uint8List> fakeHash(String pin, Uint8List salt) async =>
    Uint8List.fromList([...utf8.encode(pin).reversed, ...salt]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  var now = DateTime(2026, 10, 26, 20);
  AppLock lock() => AppLock(prefs, hasher: fakeHash, clock: () => now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 10, 26, 20);
  });

  test('only 6–8 digit PINs are accepted', () async {
    for (final bad in ['12345', '123456789', '12a456', '']) {
      expect(() => lock().setPin(bad), throwsArgumentError);
    }
    await lock().setPin('123456');
    expect(lock().enabled, isTrue);
  });

  test('real Argon2id hash verifies and never stores the PIN', () async {
    final real = AppLock(prefs);
    await real.setPin('20261026');
    final stored = prefs.getKeys().map((k) => '${prefs.get(k)}').join();
    expect(stored, isNot(contains('20261026')));
    expect(await real.verify('20261026'), isTrue);
    expect(await real.verify('20261027'), isFalse);
  });

  test('failures block even the right PIN and survive a restart', () async {
    await lock().setPin('123456');
    for (var i = 0; i < AppLock.freeAttempts; i++) {
      expect(await lock().verify('000000'), isFalse);
    }
    expect(lock().blockedFor, const Duration(seconds: 30));
    expect(await lock().verify('123456'), isFalse);
    now = now.add(const Duration(seconds: 31));
    expect(await lock().verify('123456'), isTrue);
    expect(lock().blockedFor, isNull);
  });

  test('disable removes hash and biometric flag', () async {
    await lock().setPin('123456');
    await prefs.setBool(AppLock.biometricKey, true);
    await lock().disable();
    expect(lock().enabled, isFalse);
    expect(lock().biometric, isFalse);
  });

  testWidgets('locked app hides data until PIN, relocks on leaving',
      (tester) async {
    await lock().setPin('123456');
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => LockGate(
          lock: lock(),
          biometricAuth: () async => false,
          child: child!),
      home: const Text('SALDO 462,50'),
    ));
    expect(find.text('SALDO 462,50'), findsNothing);
    expect(find.text('SALDO 462,50', skipOffstage: false), findsOneWidget);

    for (final d in '123456'.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(find.text('SALDO 462,50'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // No frames while paused: the first frame after coming back is the lock.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('SALDO 462,50'), findsNothing);
  });

  testWidgets('own sheets (picker, biometric) do not relock', (tester) async {
    await lock().setPin('123456');
    await prefs.setBool(AppLock.biometricKey, true);
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => LockGate(
          lock: lock(), biometricAuth: () async => true, child: child!),
      home: const Text('SALDO'),
    ));
    await tester.pumpAndSettle(); // biometric prompt runs on first frame
    expect(find.text('SALDO'), findsOneWidget);

    final binding = tester.binding;
    await withOwnSheet(() async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
    });
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('SALDO'), findsOneWidget);
  });
}
