import 'package:budget_simple/database/tables.dart';
import 'package:budget_simple/struct/database_global.dart' as globals;
import 'package:budget_simple/widgets/transaction_entry.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransactionsDatabase db;
  late Transaction original;
  final date = DateTime.utc(2026, 10, 26, 12);

  setUp(() async {
    db = TransactionsDatabase(NativeDatabase.memory());
    globals.database = db;
    globals.currencyIcon = '€';
    globals.language = 'es';
    globals.dataSetTranslationsApp = {};
    await db.into(db.transactions).insert(TransactionsCompanion(
        id: const Value(7),
        name: const Value('Descripción inicial'),
        amount: const Value(-12.75),
        dateCreated: Value(date)));
    original = await db.getTransaction(7);
  });
  tearDown(() => db.close());

  test('changes only description, preserving id amount and date', () async {
    expect(await db.updateTransactionName(7, 'Descripción corregida'), 1);
    final edited = await db.getTransaction(7);
    expect(edited.name, 'Descripción corregida');
    expect(edited.id, original.id);
    expect(edited.amount, original.amount);
    expect(edited.dateCreated, original.dateCreated);
    expect(await db.updateTransactionName(999, 'No existe'), 0);
    expect((await db.select(db.transactions).get()).length, 1);
  });

  test('invalid descriptions are rejected without writes; empty is allowed',
      () async {
    await expectLater(
        db.updateTransactionName(7, 'x' * 1001), throwsArgumentError);
    await expectLater(
        db.updateTransactionName(7, 'a\u0000b'), throwsArgumentError);
    expect((await db.getTransaction(7)).name, original.name);
    expect(await db.updateTransactionName(7, ''), 1);
    expect((await db.getTransaction(7)).name, '');
  });

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TransactionEntry(transaction: original))));
    await tester.tap(find.text('Descripción inicial'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Editar descripción'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        original.name);
  }

  testWidgets('cancel edit does not modify the movement', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'Cambio cancelado');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() => db.getTransaction(7));
    expect(saved, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'save edit preserves financial data and existing movement identity',
      (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'Cambio guardado');
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    final saved = (await tester.runAsync(() => db.getTransaction(7)))!;
    expect(saved.name, 'Cambio guardado');
    expect(saved.amount, original.amount);
    expect(saved.dateCreated, original.dateCreated);
    expect(saved.id, original.id);
    expect(tester.takeException(), isNull);
  });
}
