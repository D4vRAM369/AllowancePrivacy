import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:budget_simple/database/tables.dart';
import 'package:budget_simple/backup/backup_service.dart';
import 'package:budget_simple/backup/data_transfer.dart';
import 'package:budget_simple/backup/backup_platform.dart';
import 'package:budget_simple/backup/backup_crypto.dart';

class FakePlatform extends BackupPlatform {
  Uint8List? written;
  Map<String, dynamic>? keyMaterial;
  String? usedGeneration;
  @override
  Future<Map<String, dynamic>?> material() async => keyMaterial;
  @override
  Future<void> writeAutomatic(Uint8List bytes, String generation) async {
    written = bytes;
    usedGeneration = generation;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransactionsDatabase db;
  late SharedPreferences prefs;
  late BackupService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'currencyIcon': '€',
      'themeMode': 'Dark',
      'hasOnboarded': true,
      'notifications': false,
      'test_secret': 'must-not-export'
    });
    prefs = await SharedPreferences.getInstance();
    db = TransactionsDatabase(NativeDatabase.memory());
    await db.into(db.spendingLimit).insert(SpendingLimitCompanion.insert(
        id: const Value(1),
        amount: 500,
        dateCreated: Value(DateTime.utc(2026, 10, 1)),
        dateCreatedUntil: Value(DateTime.utc(2026, 11, 1))));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
        name: 'prueba',
        amount: -12.75,
        dateCreated: Value(DateTime.utc(2026, 10, 2))));
    service = BackupService(db, prefs);
  });
  tearDown(() => db.close());

  test('logical backup restores amounts and admitted preferences only',
      () async {
    final bytes = await service.createBackup();
    expect(utf8.decode(bytes), isNot(contains('must-not-export')));
    expect(utf8.decode(bytes), isNot(contains('notifications')));
    final parsed = await service.parseBackup(bytes);
    await db.delete(db.transactions).go();
    await prefs.setString('currencyIcon', '\$');
    await service.restore(parsed);
    expect((await db.select(db.transactions).get()).single.amount, -12.75);
    expect(prefs.getString('currencyIcon'), '€');
    expect(prefs.getBool('hasOnboarded'), true);
    expect(prefs.getBool('notifications'), false);
    expect(prefs.getString('test_secret'), 'must-not-export');
  });

  test('unknown format and oversized backups do not mutate financial data',
      () async {
    await expectLater(
        service.parseBackup(Uint8List.fromList(utf8.encode('{}'))),
        throwsFormatException);
    await expectLater(service.parseBackup(Uint8List(20 * 1024 * 1024 + 1)),
        throwsFormatException);
    expect((await db.select(db.transactions).get()).length, 1);
  });

  test('failed replace rolls back existing movements and preferences',
      () async {
    await db.customStatement(
        "CREATE TRIGGER deny_replace BEFORE INSERT ON transactions WHEN NEW.name='blocked' BEGIN SELECT RAISE(ABORT,'test'); END");
    final data = await service.snapshot();
    final invalid = BackupData(budget: data.budget, preferences: const {
      'currencyIcon': 'x'
    }, transactions: [
      TransferRow(name: 'blocked', amount: 1, date: DateTime.utc(2026, 10, 4))
    ]);
    await expectLater(service.restore(invalid), throwsA(anything));
    expect((await db.select(db.transactions).get()).single.name, 'prueba');
    expect(prefs.getString('currencyIcon'), '€');
  });

  test('AutoBackup without available key never writes a plain backup',
      () async {
    final platform = FakePlatform();
    final automatic = BackupService(db, prefs, platform: platform);
    await expectLater(automatic.runAutomatic(), throwsStateError);
    expect(platform.written, isNull);
  });
  test('automatic backup is portable encrypted data tied to configuration generation', () async {
    const password = 'long-passphrase-test';
    final material = await BackupCrypto.createMaterial(password);
    final platform = FakePlatform()..keyMaterial = {
      ...material, 'generation': 'configuration-1',
    };
    await BackupService(db, prefs, platform: platform).runAutomatic();
    expect(platform.usedGeneration, 'configuration-1');
    expect(BackupCrypto.isEncrypted(platform.written!), isTrue);
    final plain = await BackupCrypto.decrypt(platform.written!, password);
    final restored = await service.parseBackup(plain);
    expect(restored.transactions.single.amount, -12.75);
    expect(material['key'], everyElement(0));
  });


  test('restore notifies the streams the home screen is watching', () async {
    // Same split read/write connections as lib/database/platform/native.dart.
    final dir = await Directory.systemTemp.createTemp('restore_stream');
    final file = File('${dir.path}/db.sqlite');
    await db.close();
    db = TransactionsDatabase(MultiExecutor(
        read: NativeDatabase(file),
        write: NativeDatabase.createInBackground(file)));
    await db.into(db.spendingLimit).insert(SpendingLimitCompanion.insert(
        id: const Value(1),
        amount: 500,
        dateCreated: Value(DateTime.utc(2026, 10, 1)),
        dateCreatedUntil: Value(DateTime.utc(2026, 11, 1))));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
        name: 'prueba',
        amount: -12.75,
        dateCreated: Value(DateTime.utc(2026, 10, 2))));
    service = BackupService(db, prefs);
    final parsed = await service.parseBackup(await service.createBackup());
    final totals = <double?>[];
    final sub = db.totalSpendAfterDay(DateTime.utc(2026, 9, 30)).listen(totals.add);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
        name: 'despues', amount: 5, dateCreated: Value(DateTime.utc(2026, 10, 3))));
    await pumpEventQueue();
    expect(totals.last, -7.75);
    await service.restore(parsed);
    await pumpEventQueue();
    expect(totals.last, -12.75);
    await DataTransfer(db).importCsv([
      TransferRow(name: 'csv', amount: -1, date: DateTime.utc(2026, 10, 4))
    ]);
    await pumpEventQueue();
    expect(totals.last, -13.75);
    await sub.cancel();
    await db.close();
    db = TransactionsDatabase(NativeDatabase.memory());
    await dir.delete(recursive: true);
  });
}
