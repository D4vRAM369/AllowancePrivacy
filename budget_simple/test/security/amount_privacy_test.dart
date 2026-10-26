import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_simple/security/app_lock.dart';
import 'package:budget_simple/security/lock_gate.dart';
import 'package:budget_simple/struct/database_global.dart';
import 'package:budget_simple/struct/functions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    currencyIcon = '\$';
    amountsHidden.value = false;
  });

  test('hidden mode changes the text, never the number', () {
    const balance = 500 - 25 - 12.5;
    expect(formatAmount(balance), contains('462'));
    amountsHidden.value = true;
    expect(formatAmount(balance), '••••');
    expect(formatAmount(-0.01), '••••');
    expect(balance, 462.5);
  });

  testWidgets('leaving the app re-hides amounts when the setting is on',
      (tester) async {
    SharedPreferences.setMockInitialValues({hideAmountsKey: true});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => LockGate(lock: AppLock(prefs), child: child!),
      home: const SizedBox(),
    ));
    amountsHidden.value = false; // user tapped the eye
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    expect(amountsHidden.value, isTrue);
  });
}
