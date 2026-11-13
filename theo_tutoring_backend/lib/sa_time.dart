// ---------------------------------------------------------------------------
// SOUTH AFRICAN TIME IN SQL
// Lesson dates and times (Booking.Date, StartTime, EndTime) are stored in
// South African Standard Time (UTC+2, no daylight saving). The shared Aiven
// database runs on UTC, so NOW(), CURDATE() and CURTIME() are two hours
// behind and must not be compared with lesson times. Use these instead.
//
// Columns MySQL fills in itself (Created_at, Paid_At, ...) are on the server
// clock, so comparing those with NOW() is still correct.
// ---------------------------------------------------------------------------

/// The current date and time in South Africa, e.g. for
/// `TIMESTAMP(b.Date, b.StartTime) <= $saNowSql`.
const saNowSql = '(UTC_TIMESTAMP() + INTERVAL 2 HOUR)';

/// Today's date in South Africa (instead of CURDATE()).
const saTodaySql = 'DATE(UTC_TIMESTAMP() + INTERVAL 2 HOUR)';

/// The current time of day in South Africa (instead of CURTIME()).
const saClockSql = 'TIME(UTC_TIMESTAMP() + INTERVAL 2 HOUR)';

/// Converts a column MySQL filled in on its own clock (DEFAULT
/// CURRENT_TIMESTAMP, NOW()) to UTC, whatever time zone the server uses:
/// UTC on Aiven, South African time on a local Windows MySQL.
String serverClockToUtcSql(String column) =>
    'TIMESTAMPADD(SECOND, TIMESTAMPDIFF(SECOND, NOW(), UTC_TIMESTAMP()), '
    '$column)';
