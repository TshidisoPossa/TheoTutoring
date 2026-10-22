# Database migrations

There is no migration runner. Apply `001_booking_foundation.sql`, then
`002_booking_purchase_idempotency.sql`, after the base `schema.sql`, from one
deployment process with booking writes stopped. Each ledger version is written
last by its migration.

## `001_booking_foundation.sql`

Adds `BookingPurchase` (single/package price snapshot), `PaymentAttempt`
(purchase-scoped idempotent payment attempts), `PurchasePayment` (one successful
purchase-wide settlement), `BookingSlotHold`, `BookingReschedule`, and
`RefundTransaction`. It adds nullable purchase/lesson-price and Meet-link audit
fields to `Booking`, and amount/exception-review fields to `Refund`. Existing
tables, rows, status enums, `Payment`, and the unique `Refund.BookingID` remain.
No rates, payment credentials, bookings, or customer data are seeded.

## `002_booking_purchase_idempotency.sql`

Adds nullable `BookingPurchase.IdempotencyKey` and
`BookingPurchase.RequestFingerprint` plus the `chk_purchase_idempotency_fields`
check and `uq_purchase_student_idempotency` unique key. The columns remain
nullable solely to preserve any purchase rows created before this migration;
new application writes always provide both. Idempotency keys are scoped to a
student, compared case-sensitively, and fingerprints are SHA-256 hex digests of
canonical request JSON.

This is an additive follow-up because the foundation migration may already
have been applied. Do not rewrite or rerun an applied migration to add these
fields.

### Time and booking constraints

`Booking.Date`, `StartTime`/`EndTime`, held slots, availability, and reschedule
slots remain SQL `DATE`/`TIME` values interpreted as
`Africa/Johannesburg` local wall-clock values—not UTC instants. UTC-suffixed
audit and hold expiry fields are UTC `DATETIME(6)` values set by the backend.
Existing unqualified `DATETIME` values are not converted.

Backend code must require a 60-minute lesson, start strictly more than two
hours ahead, and a date no more than 90 days ahead. It must also verify the
entire slot falls inside that weekday's configured `TutAvailability` window.
The migration preserves legacy bookings; its 60-minute check applies only to
new purchase-linked rows. Availability changes must not erase availability
needed by confirmed bookings: reject such changes until those lessons are
lawfully moved/cancelled.

### Required serialization protocol

Every booking/hold create or change, hold expiry/release, payment outcome or
reconciliation, cancellation, and reschedule must use an InnoDB transaction.
Use one lock order everywhere:

1. For each affected lesson, derive its student and tutor before locking.
   Always lock `StudentProfile` first (`SELECT ... FOR UPDATE`), then
   `TutorProfile` (`... FOR UPDATE`); never lock a student after a tutor. This
   applies to student/tutor cancellation, rescheduling, expiry and payment
   reconciliation too. Availability-only edits lock the tutor and must never
   subsequently acquire a student lock. Serialize multi-lesson work in
   ascending student ID, then tutor ID order. Package lessons share one tutor.
   The purchase-creation endpoint uses a separate MySQL connection per
   request, InnoDB transactions, and these existing parent rows as mutexes.
   It explicitly sets MySQL `REPEATABLE READ`; reads that recheck conflicts use
   locking/current reads (`FOR UPDATE`).
   This deliberately does not rely on an empty-result gap lock: all writers
   must acquire the same persisted student/tutor parent locks before checking
   and inserting. A writer that bypasses the protocol can still double-book.
2. While holding these locks, lock rows in this order: `BookingPurchase`,
   `Booking`, `BookingSlotHold`, `PaymentAttempt`, `PurchasePayment`, `Refund`,
   `RefundTransaction`, then `BookingReschedule`; order each table's rows by
   primary key. Package refund reconciliation locks the purchase and all its
   lesson/refund rows in this order, so parallel lesson refunds cannot exceed
   the shared purchase balance. Keep the transaction open through validation
   and writes.
3. Before inserting/changing a slot, expire stale active holds for the tutor
   using UTC now. Check half-open overlap (`existing.start < proposed.end AND
   existing.end > proposed.start`) against (a) this tutor's Confirmed bookings
   and unexpired Active holds, and (b) this student's Confirmed bookings and
   unexpired Active holds across all tutors. Exclude only the same booking or
   `(PurchaseID, LessonNumber)` being changed. The student lock serializes
   cross-tutor student checks; the tutor lock serializes cross-student tutor
   checks. This prevents hold/booking and booking/booking conflicts only if
   every writer follows the protocol. SQL indexes do not enforce interval
   exclusion.
4. Set all holds in a purchase to the same expiry, exactly ten minutes after
   their shared UTC creation time.
   Reuse its unique `(PurchaseID, LessonNumber)` row on reacquisition. Payment
   reconciliation may confirm only while every required hold is still active
   and secure; a late/uncertain success after expiry is reconciliation/refund
   work, never an unreserved confirmation.

The booking indexes support lookups but do not enforce interval exclusion.
All code paths, scheduled expiry workers, availability edits, and administrative
actions must obey the same lock order and checks.

### Prices, payments, refunds, and dashboard compatibility

The purchase constraint checks subtotal = rate × lesson count, discount =
rounded subtotal × discount percentage, and total = subtotal − discount.
The backend must derive the rate from `PlatformSettings.TutoringRate`, never
accept a client price, calculate with exact decimal/integer-cent arithmetic,
and ensure allocated `Booking.LessonPriceAtPurchase` snapshots are inserted
once, never rewritten, and sum exactly to the purchase total. Discount is
exactly 10% for packages of 10+ lessons and 0% otherwise.

For exact cent allocation, distribute the purchase total in cents across
`LessonCount` deterministically (base cents per lesson, with remaining cents
assigned in lesson-number order). Store each allocation once in its booking
row; sum must equal `TotalAmount`. MySQL checks the purchase arithmetic and
payment-attempt/settlement totals, but cannot enforce cross-row allocation
sums or prevent later snapshot edits; backend write paths must do so.

`PaymentAttempt` is scoped to a purchase, so a package is charged once for its
whole total. Version 1 has only `PaymentMode = 'Demo'`; `Successful` requires
`SimulatedSuccess`, `Failed` requires `SimulatedFailure`, and unresolved
attempts may be `NotApplicable`. The schema adds no real provider or card-data
collection. Composite foreign
keys require each attempt and settlement amount to equal its purchase total,
and require the settlement's attempt to belong to that same purchase. For a
successful attempt, insert one `PurchasePayment` row under the purchase lock;
unique purchase/attempt keys make reconciliation idempotent. For a single
lesson, `PaymentID` may link the existing one-booking `Payment` row. For a
package, leave `PaymentID` NULL: the legacy table requires one `BookingId`
and cannot truthfully represent a purchase-wide charge. Do not create one
legacy payment per package lesson. A second successful attempt must be
reconciled against the existing settlement, not charged or confirmed again.
Return an existing attempt for a repeated `(PurchaseID, IdempotencyKey)`.
Serialize attempt creation on the purchase and do not create a different-key
attempt while an earlier one is `Pending`, `OutcomeUnknown`, or
`ReconciliationRequired`; reconcile it first.
If `PaymentID` is non-NULL, backend code must additionally verify the purchase
is a single lesson and that the legacy payment's `BookingId` is that purchase's
only booking. The foreign key alone cannot prove that relationship.

### Controlled demo payment endpoint

The backend-only demo endpoint records a purchase-scoped `PaymentAttempt` and,
on simulated success, one `PurchasePayment`; it never calls a payment provider
or accepts a client amount/student identity. It may be enabled only when the
process environment sets `APP_ENV` to exactly `development` or `test` and
`DEMO_PAYMENTS_ENABLED=true`. `APP_ENV` is read from the process environment,
not `.env`, so a production process always disables demo payments regardless
of dotenv values. Missing/invalid values disable the endpoint.

`POST /StudentlandingPage/booking-purchases/{purchaseId}/payment-attempts` accepts exactly
`idempotencyKey`, `paymentMethod` (`CreditDebitCard`, `PayPal`, or `EFT`), and
`simulatedOutcome` (`success` or `failure`). It returns attempt ID/number,
payment and purchase statuses, `replayed`, and `settled`; a new attempt returns
201, an identical replay 200, a disabled endpoint 403, and a rejected purchase
409. It returns no client-supplied amount or identity.

Payment writes use the required serialization protocol above. Retries use a
new idempotency key only after a failed attempt and while every required hold
is active and unexpired. Same-key requests replay only when payment method and
simulated outcome match. Success, settlement, purchase-paid, booking-confirmed,
and hold-consumed changes are one transaction. Failure records only the failed
attempt. Expiry reconciliation releases the remaining active holds and marks
the purchase expired atomically; no expired purchase is confirmed.

Package lesson rows remain individual `Booking` records, preserving tutor
dashboard queries/statuses. Require exactly `LessonCount` scheduled lessons
and active holds before initiating payment. After successful purchase
settlement, in one transaction, transition the purchase to `Paid` and each
scheduled lesson from `Pending` to `Confirmed` exactly once. Retries return
the existing settlement; failures/expiry leave lessons unconfirmed. A late or
uncertain success after a hold expires must be reconciled; do not confirm
unless every required slot is still secured.

`Refund` remains the one policy/case aggregate per booking. Its
`RefundAmount` is the approved lifetime aggregate target, not a transaction
amount. `RefundTransaction` records multiple idempotent monetary attempts for
that case. Under the refund-case and (when present) purchase locks, the backend
must cap pending, successful and uncertain transactions across every lesson in
the purchase against the allowed refundable balance; reconcile
`OutcomeUnknown` before retrying, and never refund the same amount twice.
Existing refund records are preserved and receive no invented transactions.
The schema does not itself calculate policy tiers, prove refund outcomes, or
enforce immutability/aggregate sums.
Refund transaction rows are accounting/audit records; version 1 does not
initiate real payouts or integrate a refund provider.

Backend policy remains: 100% at least 48 hours before lesson start, 50% from
24 hours to less than 48 hours, and no standard refund under 24 hours;
completed lessons are not refundable. Calculate package refunds from each
lesson's immutable discounted allocation. Exceptional refunds require an
explicit admin decision. A purchase-level lock and aggregate cap prevent
separate lesson cases exceeding the purchase balance.

Keep existing `RefundStatus` values: use `Pending`/`Approved` for the case
lifecycle and set `Processed` only when its approved target has been fully
settled; transaction-level progress belongs in `RefundTransaction`. Existing
rows with a `NULL` amount remain unchanged until explicitly reconciled.

Rescheduling must validate the proposed slot against the same availability,
90-day, lead-time, overlap and locking rules. Apply the new slot and mark the
reschedule `Applied` in one transaction; a failed validation/write must leave
the original booking date/time/status unchanged. Apply cancellation policy
using the original lesson start where the cancellation is part of the
reschedule. `Booking.Link` remains the Meet URL; only the assigned tutor may
write it, with `LinkUpdatedByUserID`/`LinkUpdatedAtUtc` set in that same
transaction. The foreign key records an existing user, not their tutor
authorization; backend code must verify role and assignment.

All new foreign keys intentionally match the base schema's signed `INT`
identifiers (`StudentProfile.StudentID`, `TutorProfile.TutorID`,
`Subjects.subjectId`, `User.UserId`, `Booking.Booking_id`, `Admin.AdminID`,
`Refund.RefundID`, and `Payment.PaymentID`). New `PurchaseID` and
`PaymentAttemptID` references are `BIGINT UNSIGNED`. The composite booking
foreign key is supported by `uq_purchase_identity`; the hold's composite
purchase/tutor foreign key is supported by `uq_purchase_tutor`.

### Apply, verify, and recover

Assumptions: MySQL 8.0.16+, InnoDB base tables, enforced `CHECK` constraints,
fractional-second `DATETIME`, and permission to create/drop a stored procedure
and alter/create tables. MySQL 8.0.16+ enforces `CHECK`; earlier 8.0 releases
may ignore them and are unsupported. Stored procedures, foreign keys and
`DATETIME(6)` are supported. `DELIMITER` is a client command; use a client
that supports it, for example:

Apply in this order: back up and check prerequisites; stop booking writes;
start one interactive client; `SOURCE` migration 001, then 002; inspect both
ledger entries and all table definitions/constraints; only then deploy
backend code and resume writes.

```powershell
mysql --default-character-set=utf8mb4 --user=YOUR_DB_USER --password theotutoring
```

```sql
SOURCE theo_tutoring_backend/database/migrations/001_booking_foundation.sql;
SOURCE theo_tutoring_backend/database/migrations/002_booking_purchase_idempotency.sql;
```

MySQL DDL implicitly commits; neither migration is atomic and neither can be
rolled back with `ROLLBACK`. Each ledger row is inserted only after its DDL, but
`CREATE TABLE IF NOT EXISTS` does not validate an existing table's structure.
Before deployment, back up the database, confirm the base schema and all
referenced keys exist, confirm InnoDB, check the required
`PlatformSettings.TutoringRate` row is configured (do not add a default), and
confirm the ledger version is absent.

Migration 002 is additive. If backend rollout is rolled back, stop purchase
creation and retain its nullable columns/index; do not drop them because
idempotency records may already exist. Repair or rollback DDL only through a
separately reviewed additive migration after inspecting actual objects.

The file is `001_booking_foundation.sql`, but its internal version remains
`20261019_01_booking_foundation`. Apply this file only where that version has
not already been recorded. If an older revision of that version was applied,
do not rerun this file or alter the ledger; apply corrections with a separately
reviewed additive follow-up migration.
After any error, keep booking writes stopped and do not blindly rerun:

1. Inspect `SchemaMigrations`, `SHOW CREATE TABLE` for every migration-created
   table and altered base table, plus `information_schema.COLUMNS`,
   `STATISTICS`, `TABLE_CONSTRAINTS`, and `KEY_COLUMN_USAGE`.
2. Compare exact columns/types/signedness, keys, indexes, checks and foreign
   key targets with this migration and `schema.sql`. If the ledger row exists
   but anything differs, do not rerun; reconcile with a reviewed, additive
   repair. If the ledger row is absent and every existing migration-created
   table is structurally complete and matches the expected definition, the
   script's guards can finish missing base-table columns/constraints and tables.
   If an existing table is partial or differs, first apply a reviewed additive
   repair and verify it; `CREATE TABLE IF NOT EXISTS` will not complete or
   validate that table. Never drop tables/constraints to make a retry pass;
   preserve their data and investigate unexpected definitions.
3. Retry only when all existing objects are confirmed compatible; verify every
   object and both expected ledger rows before deploying backend code.

Manual checks after a separately approved application:

```sql
SELECT Version, AppliedAt FROM SchemaMigrations
WHERE Version IN (
  '20261019_01_booking_foundation',
  '002_booking_purchase_idempotency'
);
SHOW CREATE TABLE BookingPurchase;
SHOW CREATE TABLE Booking;
SHOW CREATE TABLE Payment;
SHOW CREATE TABLE PaymentAttempt;
SHOW CREATE TABLE PurchasePayment;
SHOW CREATE TABLE BookingSlotHold;
SHOW CREATE TABLE BookingReschedule;
SHOW CREATE TABLE Refund;
SHOW CREATE TABLE RefundTransaction;
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
    'BookingPurchase', 'PaymentAttempt', 'PurchasePayment',
    'BookingSlotHold', 'BookingReschedule', 'RefundTransaction',
    'Booking', 'Refund'
  )
ORDER BY TABLE_NAME, CONSTRAINT_NAME;
```

Before production use, test on a disposable instance of the supported MySQL
version: clean install, migration run and rerun, a simulated partial-DDL
recovery, concurrent overlapping tutor and cross-tutor student bookings,
hold expiry during payment, duplicate/late payment outcomes, package price
allocation, concurrent/uncertain refunds, cancellation thresholds,
rescheduling failure atomicity, time-zone boundaries, availability edits with
confirmed lessons, and tutor dashboard compatibility. These runtime tests
were not performed by this static review.

### Purchase-hold endpoint deployment

Before enabling `POST /StudentlandingPage/booking-purchases`, apply and verify migration
001 and then migration 002. The route expects both idempotency columns and
their unique key. It inserts a `BookingPurchase` in `Held`, scheduled lesson
rows in `Pending`, and one `Active` `BookingSlotHold` per lesson; it never
confirms lessons or creates payment rows. The ten-minute UTC expiry is based
on database UTC time.

The route requires a verified Firebase bearer token. JSON requests provide
`tutorId`, `subjectId`, `purchaseType`, `schedulingMode`, and
`idempotencyKey`; manual schedules provide every lesson's `date`, `startTime`,
and `endTime`, while weekly package schedules provide `recurrence` with
`firstDate`, `startTime`, and `lessonCount` (the server generates seven-day
intervals). Lesson times are local `Africa/Johannesburg`. No student ID, price,
payment status, or expiry is accepted from the client. A new hold returns
201; an identical idempotent replay returns 200. Invalid input returns 400,
authentication 401, inactive students 403, missing tutor/subject 404, slot or
idempotency conflicts 409, temporary database failure 503, and unexpected
failure 500.

Creation checks conflicts after taking the student lock and then tutor lock.
The stable parent-row locks serialize two students competing for one tutor
and one student competing across tutors, even when no conflicting booking or
hold row exists yet. Conflict reads are performed in the same transaction
before inserting all lessons and holds. Duplicate slots within one request
are rejected before the transaction. The student-scoped unique key provides
a second idempotency guard; same-key retries compare the canonical request
fingerprint while holding the student lock. A same-key/different-request
retry returns conflict.

The driver is not a MySQL server and no live database was used to validate
transaction behavior, isolation, row-lock scope, SQL parameter handling, or
rollback. Before enabling this route, run the documented disposable-MySQL
concurrency/rollback tests against the supported server version. Keep every
other booking, expiry, payment, cancellation, reschedule and availability
writer on the same lock order.

Purchase-linked `Pending` lesson rows are deliberately excluded from the
tutor-dashboard pending-request cards and count. After the later payment
milestone settles a purchase and confirms its lessons, existing confirmed
schedule queries will show those individual lessons unchanged.
