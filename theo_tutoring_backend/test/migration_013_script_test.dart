// Static checks on migration 013 (no database): what it may and may not do.
// The behaviour itself is tested against MySQL 8.4 in
// test/integration/migration_013_db_test.dart.
import 'dart:io';

import 'package:test/test.dart';

import 'support/sql_script.dart';

void main() {
  final script = File(
    'database/migrations/013_payout_payment_tracking.sql',
  ).readAsStringSync();
  final statements = sqlScriptStatements(script);
  final procedure = statements.singleWhere(
    (s) => s.startsWith('CREATE PROCEDURE apply_013_payout_payment_tracking'),
  );

  test('splits into the statements the mysql client would send', () {
    expect(statements, [
      'DROP PROCEDURE IF EXISTS apply_013_payout_payment_tracking',
      procedure,
      'CALL apply_013_payout_payment_tracking()',
      'DROP PROCEDURE IF EXISTS apply_013_payout_payment_tracking',
      startsWith('INSERT IGNORE INTO schemamigrations (Version)'),
    ]);
    expect(procedure, endsWith('END'));
  });

  test('runs in the connected database and names tables in lowercase', () {
    expect(script, isNot(contains(RegExp(r'^\s*USE\s', multiLine: true))));
    final sql = statements.join('\n');
    final tables = {
      for (final m in RegExp(
        r'\b(?:ALTER TABLE|CREATE TABLE|INTO|FROM|UPDATE|REFERENCES|JOIN)\s+'
        '`?([A-Za-z_]+)`?',
      ).allMatches(sql))
        m.group(1)!,
      for (final m in RegExp(r"TABLE_NAME = '(\w+)'").allMatches(sql))
        m.group(1)!,
    }..removeAll({'information_schema'});
    expect(tables, {
      'bookingpurchase',
      'payout',
      'admin',
      'payoutadminaction',
      'platformsettings',
      'schemamigrations',
    });
  });

  test('never drops or narrows anything', () {
    final sql = statements.join('\n').toUpperCase();
    for (final banned in [
      'DROP TABLE',
      'DROP COLUMN',
      'DROP CHECK',
      'DROP FOREIGN KEY',
      'TRUNCATE',
      'DELETE FROM',
    ]) {
      expect(sql, isNot(contains(banned)), reason: banned);
    }
  });

  test('the backfill only fills unresolved rows, on evidence', () {
    final update = RegExp(
      r'UPDATE bookingpurchase[\s\S]*?;',
    ).firstMatch(procedure)!.group(0)!;
    expect(update, contains("CommissionSource = 'Backfilled'"));
    expect(update, contains('CommissionPercentage IS NULL'));
    expect(update, contains('CommissionSource IS NULL'));
    expect(
      update,
      contains('CreatedAtUtc >= TIMESTAMPADD(SECOND, 1, v_boundary)'),
    );
    expect(update, contains('PurchaseID > 0')); // safe-update mode
    // It only runs when both the rate and the evidence boundary are known.
    expect(
      procedure,
      contains('IF v_rate IS NOT NULL AND v_boundary IS NOT NULL THEN'),
    );
    // The session zone is trusted only when it is the server's zone.
    expect(procedure, contains('@@session.time_zone = @@global.time_zone'));
    expect(procedure, isNot(contains('CONVERT_TZ')));
  });

  test('every object has its own guard and a clear error when wrong', () {
    for (final name in [
      "COLUMN_NAME = 'CommissionPercentage'",
      "COLUMN_NAME = 'CommissionSource'",
      "CONSTRAINT_NAME = 'chk_purchase_commission_rate'",
      "CONSTRAINT_NAME = 'chk_purchase_commission_source'",
      "COLUMN_NAME = 'PaidByAdminID'",
      "COLUMN_NAME = 'PaymentReference'",
      "CONSTRAINT_NAME = 'fk_payout_paid_by'",
      "CONSTRAINT_NAME = 'chk_payout_paid_by'",
      "CONSTRAINT_NAME = 'chk_payout_reference'",
      "INDEX_NAME = 'uq_payout_action_once'",
    ]) {
      expect(procedure, contains(name), reason: name);
    }
    final messages = RegExp(
      r"MESSAGE_TEXT =\s*'([^']*)'",
    ).allMatches(procedure).map((m) => m.group(1)!).toList();
    expect(messages, hasLength(10));
    for (final message in messages) {
      // MySQL's limit for a condition's MESSAGE_TEXT.
      expect(message.length, lessThanOrEqualTo(128), reason: message);
      expect(message, startsWith('013: '));
    }
  });
}
