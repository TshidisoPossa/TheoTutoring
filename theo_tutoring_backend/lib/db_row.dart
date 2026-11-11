import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';

/// Typed column access for mysql_dart rows.
///
/// mysql_dart returns column values as `dynamic`; for this schema they are
/// always text or NULL, as the previous driver did. These helpers keep that
/// contract: NULL stays null, and any other value type is rejected rather
/// than converted.
extension DbRow on ResultSetRow {
  /// The column as text, or null when it is NULL.
  String? str(String column) => _text(colByName(column), column);

  /// The column as text; throws [StateError] when it is NULL.
  String reqStr(String column) =>
      str(column) ?? (throw StateError('Column $column is NULL'));

  /// A DATE column as `YYYY-MM-DD`, or null when it is NULL.
  ///
  /// Queries with parameters use the binary protocol, which returns DATE
  /// values as `YYYY-MM-DD 00:00:00`; both forms are accepted. The date must
  /// be a real calendar date that [BookingDate.parse] accepts, so
  /// `2026-02-30`, `0000-00-00` and years before 1000 are rejected. Throws
  /// [FormatException] for anything else.
  String? date(String column) {
    final value = str(column);
    if (value == null) return null;
    final match = _dateValue.firstMatch(value);
    if (match == null) {
      throw FormatException('Column $column is not a DATE value', value);
    }
    try {
      return BookingDate.parse(match.group(1)!).iso;
    } on FormatException catch (error) {
      throw FormatException('Column $column: ${error.message}', value);
    }
  }

  /// All columns as text, keyed by column name; NULL values stay null.
  Map<String, String?> textAssoc() => {
    for (final entry in assoc().entries)
      entry.key: _text(entry.value, entry.key),
  };
}

final _dateValue = RegExp(r'^(\d{4}-\d{2}-\d{2})(?: 00:00:00(?:\.0{1,6})?)?$');

String? _text(Object? value, String column) => switch (value) {
  null => null,
  final String text => text,
  _ => throw StateError(
    'Column $column is ${value.runtimeType}, expected text or NULL',
  ),
};
