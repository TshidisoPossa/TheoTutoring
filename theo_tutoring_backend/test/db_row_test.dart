import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/db_row.dart';

class _MockRow extends Mock implements ResultSetRow {}

/// A row whose columns hold [values] exactly as mysql_dart would return them.
ResultSetRow _row(Map<String, Object?> values) {
  final row = _MockRow();
  when(() => row.colByName(any())).thenAnswer(
    (invocation) => values[invocation.positionalArguments.first as String],
  );
  when(row.assoc).thenReturn(Map<String, dynamic>.of(values));
  return row;
}

void main() {
  group('date', () {
    test('keeps YYYY-MM-DD unchanged', () {
      expect(_row({'Date': '2026-11-03'}).date('Date'), '2026-11-03');
    });

    test('normalises the binary protocol form YYYY-MM-DD 00:00:00', () {
      expect(_row({'Date': '2026-11-03 00:00:00'}).date('Date'), '2026-11-03');
    });

    test('normalises YYYY-MM-DD 00:00:00.000000', () {
      expect(
        _row({'Date': '2026-11-03 00:00:00.000000'}).date('Date'),
        '2026-11-03',
      );
    });

    test('NULL stays null', () {
      expect(_row({'Date': null}).date('Date'), isNull);
    });

    test('accepts the leap day 2024-02-29 in both driver forms', () {
      expect(_row({'Date': '2024-02-29'}).date('Date'), '2024-02-29');
      expect(_row({'Date': '2024-02-29 00:00:00'}).date('Date'), '2024-02-29');
    });

    for (final value in [
      '2026-02-30',
      '2026-02-30 00:00:00',
      '2026-02-29',
      '0000-00-00',
      '0000-00-00 00:00:00',
      '0999-12-31',
    ]) {
      test('rejects "$value", which is not a supported calendar date', () {
        expect(
          () => _row({'Date': value}).date('Date'),
          throwsA(isA<FormatException>()),
        );
      });
    }

    for (final value in [
      '',
      'not a date',
      '2026-1-3',
      '03/11/2026',
      '20261103',
      '2026-11-03 ',
      ' 2026-11-03',
    ]) {
      test('rejects the malformed date "$value"', () {
        expect(
          () => _row({'Date': value}).date('Date'),
          throwsA(isA<FormatException>()),
        );
      });
    }

    for (final value in [
      '2026-11-03 10:30:00',
      '2026-11-03 00:00:01',
      '2026-11-03 00:00:00.000001',
      '2026-11-03T00:00:00',
      '2026-11-03 00:00',
    ]) {
      test('rejects the time portion in "$value"', () {
        expect(
          () => _row({'Date': value}).date('Date'),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('rejects a non-String value', () {
      expect(
        () => _row({'Date': DateTime.utc(2026, 11, 3)}).date('Date'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('str', () {
    test('returns the text unchanged', () {
      expect(_row({'Name': 'Thandi'}).str('Name'), 'Thandi');
      expect(_row({'Name': ''}).str('Name'), '');
    });

    test('NULL stays null', () {
      expect(_row({'Name': null}).str('Name'), isNull);
    });

    for (final value in <Object>[42, 4.5, BigInt.one, Uint8List(2), true]) {
      test('rejects ${value.runtimeType}', () {
        expect(
          () => _row({'Value': value}).str('Value'),
          throwsA(isA<StateError>()),
        );
      });
    }
  });

  group('reqStr', () {
    test('returns the text unchanged', () {
      expect(_row({'TutorID': '7'}).reqStr('TutorID'), '7');
    });

    test('NULL throws StateError', () {
      expect(
        () => _row({'TutorID': null}).reqStr('TutorID'),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a non-String value', () {
      expect(
        () => _row({'TutorID': 7}).reqStr('TutorID'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('textAssoc', () {
    test('keeps every column, its text and its nulls', () {
      final values = _row({
        'Booking_id': '12',
        'Note': null,
        'Status': 'Confirmed',
      }).textAssoc();

      expect(values, isA<Map<String, String?>>());
      expect(values, {'Booking_id': '12', 'Note': null, 'Status': 'Confirmed'});
    });

    test('rejects a non-String value', () {
      expect(
        () => _row({'Booking_id': '12', 'Photo': Uint8List(3)}).textAssoc(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
