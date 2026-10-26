import 'dart:convert';
import 'package:budget_simple/backup/data_transfer.dart';
import 'package:budget_simple/database/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 10, 26, 12);
  final budget = BudgetRecord(
      amount: 500, created: day, until: day.add(const Duration(days: 30)));
  TransferRow row(String name, [double amount = 12.5]) =>
      TransferRow(name: name, amount: amount, date: day);
  group('CSV v1', () {
    test(
        'roundtrips Unicode, fractions, quotes, multiline and formula-like names',
        () {
      final names = [
        'Café',
        'a,b',
        'dijo "hola"',
        'dos\nlíneas',
        '=SUM(A1)',
        '+cmd',
        '-text',
        '@x',
        "'literal",
        "'=x",
        ' foo',
        '\tformula',
        ''
      ];
      final original = [
        for (var i = 0; i < names.length; i++)
          row(names[i], i.isEven ? -0.125 : 1e-7)
      ];
      final encoded = TransactionCsv.encode(original);
      final decoded = TransactionCsv.decode('\uFEFF$encoded');
      expect(decoded.map((e) => e.name), names);
      expect(decoded.map((e) => e.amount), original.map((e) => e.amount));
      expect(decoded.every((e) => e.date == day), isTrue);
      expect(encoded, contains("'=SUM(A1)"));
    });
    test('allows empty movement list and LF separators', () {
      expect(TransactionCsv.decode('date,name,amount\n'), isEmpty);
      expect(
          TransactionCsv.decode(
                  'date,name,amount\n2026-10-26T12:00:00Z,Compra,-1.25\n')
              .single
              .amount,
          -1.25);
    });
    test('rejects unknown headers, malformed quoting, fields and dates', () {
      final invalid = [
        'fecha,name,amount\n',
        'date,name,amount,extra\n',
        'date,name,amount\n2026-02-30T00:00:00Z,x,1',
        'date,name,amount\n2026-10-26T25:00:00Z,x,1',
        'date,name,amount\n2026-10-26,x,1',
        'date,name,amount\n2026-10-26T00:00:00.123Z,x,1',
        'date,name,amount\n2026-10-26T00:00:00Z,x,NaN',
        'date,name,amount\n2026-10-26T00:00:00Z,x,Infinity',
        'date,name,amount\n2026-10-26T00:00:00Z,x,1000000000000000',
        'date,name,amount\n2026-10-26T00:00:00Z,"x"oops,1',
        'date,name,amount\n2026-10-26T00:00:00Z,"x,1',
        'date,name,amount\n2026-10-26T00:00:00Z,x,1,extra',
      ];
      for (final input in invalid) {
        expect(() => TransactionCsv.decode(input), throwsFormatException,
            reason: input);
      }
    });
    test('rejects oversized names and files', () {
      expect(() => TransactionCsv.encode([row('x' * 1001)]),
          throwsFormatException);
      expect(() => TransactionCsv.decode('x' * (maxTransferBytes + 1)),
          throwsFormatException);
    });
  });
  group('Backup validation', () {
    test('versioned JSON preserves IDs, budget and whitelisted settings', () {
      final data = BackupData(
          transactions: [
            TransferRow(id: 42, name: 'Original', amount: 12.125, date: day)
          ],
          budget: budget,
          preferences: {
            'currencyIcon': '€',
            'language': 'es',
            'themeMode': 'Dark',
            'hapticFeedback': false
          });
      final decoded = BackupData.fromJson(
          jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
      expect(decoded.toJson(), data.toJson());
      expect(decoded.transactions.single.id, 42);
    });
    test('rejects versions, duplicate IDs, invalid preferences and amounts',
        () {
      final data =
          BackupData(transactions: [row('x')], budget: budget).toJson();
      expect(() => BackupData.fromJson({...data, 'version': 2}),
          throwsFormatException);
      expect(
          () => BackupData.fromJson({
                ...data,
                'preferences': {'pin': '1234'}
              }),
          throwsFormatException);
      expect(
          () => BackupData.fromJson({
                ...data,
                'preferences': {'themeMode': 'invalid'}
              }),
          throwsFormatException);
      expect(
          () => BackupData.fromJson({
                ...data,
                'preferences': {'language': null}
              }),
          throwsFormatException);
      expect(
          () => BackupData(transactions: [row('x', double.nan)], budget: budget)
              .toJson(),
          throwsFormatException);
      expect(
          () => BackupData(transactions: [
                TransferRow(id: 1, name: 'a', amount: 1, date: day),
                TransferRow(id: 1, name: 'b', amount: 2, date: day)
              ], budget: budget)
                  .toJson(),
          throwsFormatException);
    });
  });
  group('Database transfers', () {
    late TransactionsDatabase db;
    late DataTransfer transfer;
    setUp(() async {
      db = TransactionsDatabase(NativeDatabase.memory());
      transfer = DataTransfer(db);
      await db.into(db.spendingLimit).insert(SpendingLimitCompanion(
          id: const Value(1),
          amount: const Value(500),
          dateCreated: Value(day),
          dateCreatedUntil: Value(budget.until)));
      await db.into(db.transactions).insert(TransactionsCompanion(
          id: const Value(7),
          name: const Value('Original'),
          amount: const Value(10.25),
          dateCreated: Value(day)));
    });
    tearDown(() => db.close());
    test('snapshot and restore preserve IDs and budget', () async {
      final copy = await transfer.snapshot();
      await transfer.importCsv([row('Added')]);
      await transfer.restore(copy);
      final restored = await transfer.snapshot();
      expect(restored.toJson(), copy.toJson());
      expect(restored.transactions.single.id, 7);
    });
    test('CSV skips exact duplicates and leaves budget unchanged', () async {
      expect(
          await transfer.importCsv(
              [row('Original', 10.25), row('New', -0.5), row('New', -0.5)]),
          1);
      expect(await transfer.importCsv([row('New', -0.5)]), 0);
      final saved = await transfer.snapshot();
      expect(saved.transactions.length, 2);
      expect(saved.budget.amount, 500);
    });
    test('restore SQL failure rolls back deletion and budget changes',
        () async {
      final before = await transfer.snapshot();
      await db.customStatement(
          "CREATE TRIGGER reject_test BEFORE INSERT ON transactions WHEN NEW.name = 'Reject' BEGIN SELECT RAISE(ABORT, 'test failure'); END");
      final replacement = BackupData(
          transactions: [row('First'), row('Reject')],
          budget: BudgetRecord(amount: 1, created: day, until: budget.until));
      await expectLater(transfer.restore(replacement), throwsA(anything));
      expect((await transfer.snapshot()).toJson(), before.toJson());
    });
    test('CSV SQL failure rolls back earlier inserts', () async {
      final before = await transfer.snapshot();
      await db.customStatement(
          "CREATE TRIGGER reject_test BEFORE INSERT ON transactions WHEN NEW.name = 'Reject' BEGIN SELECT RAISE(ABORT, 'test failure'); END");
      await expectLater(
          transfer.importCsv([row('First'), row('Reject')]), throwsA(anything));
      expect((await transfer.snapshot()).toJson(), before.toJson());
    });
    test('invalid data never changes database', () async {
      final before = await transfer.snapshot();
      await expectLater(
          transfer.importCsv([row('Good'), row('Bad', double.infinity)]),
          throwsFormatException);
      await expectLater(
          transfer.restore(BackupData(
              transactions: [row('Bad', double.nan)], budget: budget)),
          throwsFormatException);
      expect((await transfer.snapshot()).toJson(), before.toJson());
    });
  });
}
