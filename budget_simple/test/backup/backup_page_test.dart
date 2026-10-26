import 'dart:convert';
import 'package:budget_simple/backup/data_transfer.dart';
import 'package:budget_simple/database/tables.dart';
import 'package:budget_simple/pages/backup_page.dart';
import 'package:budget_simple/struct/database_global.dart' as globals;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('allowance_privacy/backup');
  final day = DateTime.utc(2026, 10, 26);
  late TransactionsDatabase db;
  late List<MethodCall> calls;
  Uint8List? pickedBytes;

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: BackupPage()));
    await tester.pumpAndSettle();
  }

  // Busy progress intentionally animates while confirmation is open.
  Future<void> showAction(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<Map<String, dynamic>> snapshot(WidgetTester tester) async =>
      (await tester
          .runAsync(() async => (await DataTransfer(db).snapshot()).toJson()))!;

  setUp(() async {
    pickedBytes = null;
    calls = [];
    SharedPreferences.setMockInitialValues({'currencyIcon': '€'});
    globals.sharedPreferences = await SharedPreferences.getInstance();
    db = TransactionsDatabase(NativeDatabase.memory());
    globals.database = db;
    await db.into(db.spendingLimit).insert(SpendingLimitCompanion(
        id: const Value(1),
        amount: const Value(500),
        dateCreated: Value(day),
        dateCreatedUntil: Value(day.add(const Duration(days: 30)))));
    await db.into(db.transactions).insert(TransactionsCompanion(
        id: const Value(7),
        name: const Value('Dato existente'),
        amount: const Value(12.5),
        dateCreated: Value(day)));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getAutoBackupStatus':
          return <String, dynamic>{
            'enabled': false,
            'folderSelected': false,
            'intervalHours': 24,
            'retention': 7
          };
        case 'readDocument':
          return pickedBytes;
        case 'writeDocument':
          return true;
        default:
          throw PlatformException(code: 'unexpected_method');
      }
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
  });

  testWidgets('shows separate CSV, complete backup and encrypted AutoBackup',
      (tester) async {
    await pumpPage(tester);
    expect(find.text('Copias y datos'), findsOneWidget);
    expect(find.text('Exportar CSV sin cifrar'), findsOneWidget);
    expect(find.text('Importar CSV sin cifrar'), findsOneWidget);
    expect(find.text('Backup completo'), findsOneWidget);
    expect(find.text('Cifrar con contraseña'), findsOneWidget);
    expect(calls.map((call) => call.method), ['getAutoBackupStatus']);
  });

  testWidgets('cancelled Android picker leaves database unchanged',
      (tester) async {
    final before = await snapshot(tester);
    await pumpPage(tester);
    await showAction(tester, 'Importar CSV sin cifrar');
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'readDocument'), hasLength(1));
    expect(find.byType(AlertDialog), findsNothing);
    expect(await snapshot(tester), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid CSV shows generic error without sensitive input',
      (tester) async {
    final before = await snapshot(tester);
    const privateInput = 'PRIVATE-ACCOUNT-998811-SALDO-12000';
    pickedBytes = Uint8List.fromList(utf8.encode(privateInput));
    await pumpPage(tester);
    await showAction(tester, 'Importar CSV sin cifrar');
    await tester.pumpAndSettle();
    expect(find.textContaining('No se completó la operación'), findsOneWidget);
    expect(find.textContaining(privateInput), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(await snapshot(tester), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CSV export warns before opening save picker', (tester) async {
    await pumpPage(tester);
    await showAction(tester, 'Exportar CSV sin cifrar');
    expect(find.text('CSV sin cifrar'), findsOneWidget);
    expect(find.textContaining('legibles por cualquiera'), findsOneWidget);
    expect(calls.where((call) => call.method == 'writeDocument'), isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'writeDocument'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CSV preview cancellation preserves financial data',
      (tester) async {
    final before = await snapshot(tester);
    pickedBytes = Uint8List.fromList(utf8.encode(TransactionCsv.encode([
      TransferRow(name: 'Movimiento nuevo', amount: -2.25, date: day),
    ])));
    await pumpPage(tester);
    await showAction(tester, 'Importar CSV sin cifrar');
    expect(find.text('Importar 1 movimientos'), findsOneWidget);
    expect(find.textContaining('Movimiento nuevo'), findsOneWidget);
    expect(find.textContaining('sin modificar el presupuesto'), findsOneWidget);
    expect(await snapshot(tester), before);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await snapshot(tester), before);
    expect(tester.takeException(), isNull);
  });
}
