import 'dart:convert';

import 'package:budget_simple/database/tables.dart';
import 'package:drift/drift.dart';

const int maxTransferRows = 100000;
const int maxTransferBytes = 20 * 1024 * 1024;

/// Interchange records deliberately omit authentication and private preferences.
class TransferRow {
  const TransferRow(
      {required this.name, required this.amount, required this.date, this.id});
  final String name;
  final double amount;
  final DateTime date;
  final int? id;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'amount': amount,
        'date': date.toUtc().toIso8601String(),
      };

  factory TransferRow.fromJson(Map<String, dynamic> map) {
    if (map['name'] is! String ||
        map['amount'] is! num ||
        (map['id'] != null && (map['id'] is! int || (map['id'] as int) < 1))) {
      throw const FormatException('Movimiento inválido.');
    }
    final row = TransferRow(
        name: map['name'] as String,
        amount: (map['amount'] as num).toDouble(),
        date: _date(map['date']),
        id: map['id'] as int?);
    _validateRow(row);
    return row;
  }
}

class BudgetRecord {
  const BudgetRecord(
      {required this.amount, required this.created, required this.until});
  final double amount;
  final DateTime created;
  final DateTime until;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'created': created.toUtc().toIso8601String(),
        'until': until.toUtc().toIso8601String()
      };

  factory BudgetRecord.fromJson(Map<String, dynamic> map) {
    if (map['amount'] is! num) {
      throw const FormatException('Presupuesto inválido.');
    }
    final budget = BudgetRecord(
        amount: (map['amount'] as num).toDouble(),
        created: _date(map['created']),
        until: _date(map['until']));
    _validateBudget(budget);
    return budget;
  }
}

class BackupData {
  BackupData(
      {required List<TransferRow> transactions,
      required this.budget,
      Map<String, Object> preferences = const {}})
      : transactions = List.unmodifiable(transactions),
        preferences = Map.unmodifiable(preferences);
  final List<TransferRow> transactions;
  final BudgetRecord budget;
  final Map<String, Object> preferences;

  Map<String, dynamic> toJson() {
    _validateBackup(this);
    return {
      'format': 'allowance-privacy-backup',
      'version': 1,
      'schemaVersion': 1,
      'budget': budget.toJson(),
      'preferences': preferences,
      'transactions': transactions.map((row) => row.toJson()).toList()
    };
  }

  factory BackupData.fromJson(Map<String, dynamic> map) {
    if (map['format'] != 'allowance-privacy-backup' ||
        map['version'] != 1 ||
        map['schemaVersion'] != 1 ||
        map['budget'] is! Map<String, dynamic> ||
        map['transactions'] is! List ||
        (map['transactions'] as List).length > maxTransferRows) {
      throw const FormatException('Formato o versión del backup no admitidos.');
    }
    final rows = <TransferRow>[];
    for (final value in map['transactions'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Movimiento inválido.');
      }
      rows.add(TransferRow.fromJson(value));
    }
    final rawPreferences = map['preferences'] ?? <String, Object>{};
    if (rawPreferences is! Map<String, dynamic> ||
        rawPreferences.values.any((value) => value == null)) {
      throw const FormatException('Preferencias inválidas.');
    }
    final data = BackupData(
        transactions: rows,
        preferences:
            rawPreferences.map((key, value) => MapEntry(key, value as Object)),
        budget: BudgetRecord.fromJson(map['budget'] as Map<String, dynamic>));
    _validateBackup(data);
    return data;
  }
}

/// Uses Drift transactions instead of copying a live database file and its WAL.
class DataTransfer {
  DataTransfer(this.db);
  final TransactionsDatabase db;

  Future<BackupData> snapshot() => db.transaction(() async {
        final budget = await db.getSpendingLimit();
        final query = db.select(db.transactions)
          ..orderBy([(table) => OrderingTerm.asc(table.id)]);
        final rows = await query.get();
        final data = BackupData(
            transactions: rows
                .map((row) => TransferRow(
                    id: row.id,
                    name: row.name,
                    amount: row.amount,
                    date: row.dateCreated))
                .toList(),
            budget: BudgetRecord(
                amount: budget.amount,
                created: budget.dateCreated,
                until: budget.dateCreatedUntil));
        _validateBackup(data);
        return data;
      });

  /// Caller must obtain explicit replacement confirmation before invoking this.
  Future<void> restore(BackupData data) async {
    _validateBackup(data);
    await db.transaction(() async {
      await db.delete(db.transactions).go();
      await db.delete(db.spendingLimit).go();
      for (final row in data.transactions) {
        await db.into(db.transactions).insert(TransactionsCompanion(
            id: row.id == null ? const Value.absent() : Value(row.id!),
            name: Value(row.name),
            amount: Value(row.amount),
            dateCreated: Value(row.date.toUtc())));
      }
      await db.into(db.spendingLimit).insert(SpendingLimitCompanion(
          id: const Value(1),
          amount: Value(data.budget.amount),
          dateCreated: Value(data.budget.created.toUtc()),
          dateCreatedUntil: Value(data.budget.until.toUtc())));
    });
  }

  /// Split read/write connections (platform/native.dart) miss transaction
  /// updates, so open screens would keep stale totals until restart.
  void notifyChanged() => db.notifyUpdates({
        TableUpdate.onTable(db.transactions),
        TableUpdate.onTable(db.spendingLimit)
      });

  /// CSV adds movements, skips exact duplicates, and leaves the budget intact.
  Future<int> importCsv(List<TransferRow> rows) async {
    _validateRows(rows);
    final added = await db.transaction(() async {
      final existing = await db.select(db.transactions).get();
      final seen = existing
          .map((row) => _rowKey(row.name, row.amount, row.dateCreated))
          .toSet();
      var added = 0;
      for (final row in rows) {
        if (!seen.add(_rowKey(row.name, row.amount, row.date))) continue;
        await db.into(db.transactions).insert(TransactionsCompanion(
            name: Value(row.name),
            amount: Value(row.amount),
            dateCreated: Value(row.date.toUtc())));
        added++;
      }
      return added;
    });
    notifyChanged();
    return added;
  }
}

String _rowKey(String name, double amount, DateTime date) => jsonEncode(
    [name, amount == 0 ? 0 : amount, date.millisecondsSinceEpoch ~/ 1000]);

void _validateAmount(double amount) {
  if (!amount.isFinite || amount.abs() >= 1e15) {
    throw const FormatException('Importe fuera de rango.');
  }
}

void _validateRow(TransferRow row) {
  if (row.name.length > 1000 || row.name.contains('\u0000')) {
    throw const FormatException('Concepto inválido.');
  }
  if (row.id != null && (row.id! < 1 || row.id! > 0x7fffffff)) {
    throw const FormatException('Identificador inválido.');
  }
  _validateAmount(row.amount);
  _validateDate(row.date);
}

void _validateBudget(BudgetRecord budget) {
  _validateAmount(budget.amount);
  _validateDate(budget.created);
  _validateDate(budget.until);
  if (budget.amount < 0 || !budget.until.isAfter(budget.created)) {
    throw const FormatException('Presupuesto inválido.');
  }
}

void _validateRows(List<TransferRow> rows) {
  if (rows.length > maxTransferRows) {
    throw const FormatException('Demasiados movimientos.');
  }
  for (final row in rows) {
    _validateRow(row);
  }
}

void _validateBackup(BackupData data) {
  for (final entry in data.preferences.entries) {
    final value = entry.value;
    final valid = switch (entry.key) {
      'currencyIcon' ||
      'language' =>
        value is String && value.length <= 16 && !value.contains('\u0000'),
      'themeMode' =>
        value is String && const ['System', 'Light', 'Dark'].contains(value),
      'hapticFeedback' => value is bool,
      _ => false,
    };
    if (!valid) throw const FormatException('Preferencias no admitidas.');
  }
  _validateRows(data.transactions);
  _validateBudget(data.budget);
  final ids = <int>{};
  for (final row in data.transactions) {
    if (row.id != null && !ids.add(row.id!)) {
      throw const FormatException('Identificadores repetidos.');
    }
  }
}

void _validateDate(DateTime date) {
  // Existing Drift columns store whole seconds; reject precision we cannot keep.
  if (date.millisecond != 0 || date.microsecond != 0) {
    throw const FormatException(
        'Las fechas deben tener precisión de segundos.');
  }
  if (date.toUtc().year < 1900 || date.toUtc().year > 9999) {
    throw const FormatException('Fecha fuera de rango.');
  }
}

DateTime _date(Object? value) {
  if (value is! String) throw const FormatException('Fecha inválida.');
  final match = RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?Z$')
      .firstMatch(value);
  if (match == null) throw const FormatException('Usa fechas ISO8601 UTC.');
  final date = DateTime.tryParse(value);
  if (date == null ||
      date.year != int.parse(match[1]!) ||
      date.month != int.parse(match[2]!) ||
      date.day != int.parse(match[3]!) ||
      date.hour != int.parse(match[4]!) ||
      date.minute != int.parse(match[5]!) ||
      date.second != int.parse(match[6]!)) {
    throw const FormatException('Fecha inválida.');
  }
  _validateDate(date);
  return date;
}

class TransactionCsv {
  static bool _escaped(String value) =>
      value.isNotEmpty &&
      (value.startsWith("'") || RegExp(r'^[\s=+@-]').hasMatch(value));

  /// V1: dangerous names have one leading apostrophe; literal apostrophes double.
  /// This is reversible for this dialect; arbitrary third-party dialects are rejected.
  static String encode(List<TransferRow> rows) {
    _validateRows(rows);
    String field(String value) => '"${value.replaceAll('"', '""')}"';
    final out = StringBuffer('date,name,amount\r\n');
    for (final row in rows) {
      final name = _escaped(row.name) ? "'${row.name}" : row.name;
      out.writeln(
          '${field(row.date.toUtc().toIso8601String())},${field(name)},${row.amount}\r');
    }
    final csv = out.toString();
    if (utf8.encode(csv).length > maxTransferBytes) {
      throw const FormatException('Archivo demasiado grande.');
    }
    return csv;
  }

  static List<TransferRow> decode(String text) {
    if (utf8.encode(text).length > maxTransferBytes) {
      throw const FormatException('Archivo demasiado grande.');
    }
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final records = _parse(text);
    if (records.isEmpty ||
        records.first.join(',') != 'date,name,amount' ||
        records.first.length != 3) {
      throw const FormatException('Cabeceras esperadas: date,name,amount.');
    }
    final rows = <TransferRow>[];
    for (final fields in records.skip(1)) {
      if (fields.length != 3 ||
          fields[1].length > 1001 ||
          !RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$')
              .hasMatch(fields[2])) {
        throw const FormatException('Fila CSV inválida.');
      }
      var name = fields[1];
      if (name.startsWith("'") && _escaped(name.substring(1))) {
        name = name.substring(1);
      }
      final amount = double.tryParse(fields[2]);
      if (amount == null) throw const FormatException('Importe inválido.');
      final row =
          TransferRow(name: name, amount: amount, date: _date(fields[0]));
      _validateRow(row);
      rows.add(row);
      if (rows.length > maxTransferRows) {
        throw const FormatException('Demasiados movimientos.');
      }
    }
    return rows;
  }

  static List<List<String>> _parse(String text) {
    final records = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var closed = false;
    var started = false;
    void finishField() {
      row.add(field.toString());
      field = StringBuffer();
      closed = false;
      started = false;
    }

    void finishRow() {
      finishField();
      records.add(row);
      row = [];
      if (records.length > maxTransferRows + 1) {
        throw const FormatException('Demasiadas filas.');
      }
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          field.write(char);
        }
      } else if (char == ',') {
        finishField();
      } else if (char == '\r' || char == '\n') {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        finishRow();
      } else if (char == '"' && !started && !closed) {
        quoted = true;
        started = true;
      } else {
        if (closed || char == '"') {
          throw const FormatException('Comillas CSV inválidas.');
        }
        field.write(char);
        started = true;
      }
    }
    if (quoted) throw const FormatException('Comillas CSV sin cerrar.');
    if (row.isNotEmpty || started || closed) finishRow();
    return records;
  }
}
