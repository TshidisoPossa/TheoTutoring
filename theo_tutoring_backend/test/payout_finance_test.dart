// The payout money rules (lib/payout_finance.dart): parsing, commission,
// eligibility, the financial overview and its reconciliation. No database.
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/payout_finance.dart';

PaidLesson _lesson(
  int id, {
  String status = 'Confirmed',
  bool ended = true,
  bool pastEnd = false,
  int price = 17500,
  int? rate = 1000,
  String? source = 'Purchase',
  String? refundStatus,
  int? refund,
  int? payoutId,
  int? payoutTotal,
}) => PaidLesson(
  bookingId: id,
  tutorId: 3,
  bookingStatus: status,
  ended: ended,
  pastEnd: pastEnd,
  priceCents: price,
  commissionRateHundredths: rate,
  commissionSource: source,
  refundStatus: refundStatus,
  refundCents: refund,
  payoutId: payoutId,
  payoutTotalCents: payoutTotal ?? (payoutId == null ? null : price),
);

List<String> _codes(Map<String, Object?> finance) => [
  for (final issue in finance['issues']! as List)
    (issue as Map)['code']! as String,
];

Map<String, Object?> _issue(Map<String, Object?> finance, String code) =>
    (finance['issues']! as List).cast<Map<String, Object?>>().singleWhere(
      (i) => i['code'] == code,
    );

void main() {
  group('money parsing and formatting', () {
    test('DECIMAL text becomes exact cents', () {
      expect(parseCents('175.00'), 17500);
      expect(parseCents('87.5'), 8750);
      expect(parseCents('12'), 1200);
      expect(parseCents('0.05'), 5);
      expect(parseCents('-5.25'), -525);
      expect(parseCents(' 10.00 '), 1000);
      expect(parseCents(null), isNull);
      expect(parseCents(''), isNull);
      expect(parseCents('abc'), isNull);
      expect(parseCents('1e3'), isNull);
    });

    test('cents format back to DECIMAL text, including negatives', () {
      expect(formatCents(17500), '175.00');
      expect(formatCents(5), '0.05');
      expect(formatCents(0), '0.00');
      expect(formatCents(-20000), '-200.00');
      expect(formatCents(-5), '-0.05');
    });

    test('commission is the rate on the price, rounded half up', () {
      expect(commissionCents(17500, 1000), 1750); // R175 at 10%
      expect(commissionCents(18500, 1000), 1850);
      expect(commissionCents(5, 1000), 1); // 0.5c rounds up
      expect(commissionCents(4, 1000), 0); // 0.4c rounds down
      expect(commissionCents(15750, 1250), 1969); // 19.6875 -> 19.69
      expect(commissionCents(17500, 0), 0);
      expect(commissionCents(17500, 10000), 17500);
      expect(() => commissionCents(-1, 1000), throwsArgumentError);
      expect(() => commissionCents(100, 10001), throwsArgumentError);
    });
  });

  group('payout eligibility', () {
    test('a finished, paid, unrefunded lesson with a rate is eligible', () {
      expect(payoutIneligibility(_lesson(1)), isNull);
      expect(payoutIneligibility(_lesson(1, status: 'Completed')), isNull);
      // a rejected refund leaves the whole price with the lesson
      expect(
        payoutIneligibility(_lesson(1, refundStatus: 'Rejected', refund: 0)),
        isNull,
      );
    });

    test('each rule that blocks a payout', () {
      expect(payoutIneligibility(_lesson(1, ended: false)), 'not_finished');
      expect(
        payoutIneligibility(_lesson(1, status: 'Cancelled')),
        'cancelled',
      );
      expect(payoutIneligibility(_lesson(1, status: 'Rejected')), 'cancelled');
      for (final refund in ['Pending', 'Approved', 'Processed']) {
        expect(
          payoutIneligibility(_lesson(1, refundStatus: refund, refund: 100)),
          'refund',
          reason: refund,
        );
      }
      expect(
        payoutIneligibility(_lesson(1, payoutId: 9)),
        'already_generated',
      );
      expect(
        payoutIneligibility(_lesson(1, rate: null, source: null)),
        'missing_rate',
      );
    });

    test('the payout is the price less the captured commission', () {
      final draft = draftPayout(_lesson(4, price: 18500)); // 10%
      expect(draft.bookingId, 4);
      expect(draft.tutorId, 3);
      expect(draft.amountCents, 18500);
      expect(draft.commissionCents, 1850);
      expect(draft.netCents, 16650);
      expect(draft.commissionCents + draft.netCents, draft.amountCents);
    });

    test("each lesson uses its own purchase's rate, not today's setting", () {
      // Two lessons bought when the rate was 10% and 15%: the setting today
      // is irrelevant, only the captured rate counts.
      expect(draftPayout(_lesson(1)).commissionCents, 1750);
      expect(draftPayout(_lesson(2, rate: 1500)).commissionCents, 2625);
      // a backfilled historical rate is used as recorded
      expect(
        draftPayout(_lesson(3, source: 'Backfilled')).netCents,
        15750,
      );
    });

    test('drafting an ineligible lesson is refused', () {
      expect(
        () => draftPayout(_lesson(1, ended: false)),
        throwsStateError,
      );
    });
  });

  group('financial overview', () {
    // A: finished, no payout yet       175.00 -> awaiting generation
    // B: upcoming                      185.00 -> held
    // C: cancelled, 100% refunded      185.00 -> refunded 185
    // D: cancelled, 50% refunded       175.00 -> refunded 87.50, kept 87.50
    // E: cancelled, refund pending     175.00 -> awaiting decision
    // F: cancelled, refund rejected    175.00 -> kept 175
    // G: payout Pending                175.00 -> 17.50 + 157.50 owed
    // H: payout Paid                   200.00 -> 20.00 + 180.00 paid
    final lessons = [
      _lesson(1),
      _lesson(2, ended: false, price: 18500),
      _lesson(
        3,
        status: 'Cancelled',
        ended: false,
        price: 18500,
        refundStatus: 'Approved',
        refund: 18500,
      ),
      _lesson(
        4,
        status: 'Cancelled',
        ended: false,
        refundStatus: 'Processed',
        refund: 8750,
      ),
      _lesson(5, status: 'Cancelled', refundStatus: 'Pending', refund: 0),
      _lesson(6, status: 'Cancelled', refundStatus: 'Rejected', refund: 0),
      _lesson(7, payoutId: 70),
      _lesson(8, price: 20000, payoutId: 80),
    ];
    const payouts = PayoutTotals(
      pendingCount: 1,
      pendingNetCents: 15750,
      paidCount: 1,
      paidNetCents: 18000,
      commissionCents: 3750,
    );
    const received = 144500; // the eight prices

    test('every category is separate and the total reconciles', () {
      final f = payoutFinanceSummary(
        receivedCents: received,
        payouts: payouts,
        lessons: lessons,
      );
      expect(f['moneyReceived'], '1445.00');
      expect(f['platformCommission'], '37.50');
      expect(f['owedToTutors'], '157.50');
      expect(f['paidToTutors'], '180.00');
      expect(f['refunded'], '272.50');
      expect(f['retainedCancellationRevenue'], '262.50');
      expect(f['awaitingRefundDecision'], '175.00');
      expect(f['heldForUpcomingLessons'], '185.00');
      expect(f['awaitingPayoutGeneration'], '175.00');
      expect(f['unallocated'], '0.00');
      expect(f['accountedFor'], '1445.00');
      expect(f['difference'], '0.00');
      expect(f['reconciled'], isTrue);
      expect(f['issues'], isEmpty);
      final counts = f['counts']! as Map;
      expect(counts['eligibleLessons'], 1);
      expect(counts['upcomingLessons'], 1);
      expect(counts['pendingPayouts'], 1);
      expect(counts['paidPayouts'], 1);
    });

    test('retained cancellation money is not counted as commission', () {
      final f = payoutFinanceSummary(
        receivedCents: 17500,
        payouts: const PayoutTotals(),
        lessons: [
          _lesson(6, status: 'Cancelled', refundStatus: 'Rejected', refund: 0),
        ],
      );
      expect(f['retainedCancellationRevenue'], '175.00');
      expect(f['platformCommission'], '0.00');
      expect(f['awaitingPayoutGeneration'], '0.00');
      expect(f['reconciled'], isTrue);
    });

    test('a refund approved after the payout is flagged and not hidden', () {
      final refundedAfter = [
        ...lessons.take(7),
        _lesson(
          8,
          price: 20000,
          payoutId: 80,
          refundStatus: 'Approved',
          refund: 20000,
        ),
      ];
      final f = payoutFinanceSummary(
        receivedCents: received,
        payouts: payouts,
        lessons: refundedAfter,
      );
      // The paid payout is unchanged; the refund is still counted.
      expect(f['paidToTutors'], '180.00');
      expect(f['refunded'], '472.50');
      expect(f['reconciled'], isFalse);
      expect(f['difference'], '-200.00');
      expect(_codes(f), containsAll(['refund_after_payout', 'unreconciled']));
      expect(_issue(f, 'refund_after_payout')['count'], 1);
      expect(_issue(f, 'refund_after_payout')['amount'], '200.00');
    });

    test('a pending refund on a lesson with a payout is flagged', () {
      final f = payoutFinanceSummary(
        receivedCents: 17500,
        payouts: const PayoutTotals(
          pendingCount: 1,
          pendingNetCents: 15750,
          commissionCents: 1750,
        ),
        lessons: [_lesson(7, payoutId: 70, refundStatus: 'Pending')],
      );
      expect(_codes(f), ['refund_pending_after_payout']);
      expect(f['reconciled'], isTrue);
    });

    test('a payout without a paid lesson shows as a difference', () {
      const withOrphan = PayoutTotals(
        pendingCount: 1,
        pendingNetCents: 15750,
        paidCount: 2,
        paidNetCents: 18000 + 4500,
        commissionCents: 3750 + 500,
      );
      final f = payoutFinanceSummary(
        receivedCents: received,
        payouts: withOrphan,
        lessons: lessons,
      );
      expect(f['difference'], '-50.00');
      expect(_issue(f, 'payout_without_paid_lesson')['amount'], '50.00');
      expect(_codes(f), contains('unreconciled'));
    });

    test('a received total that the lessons do not explain is reported', () {
      final f = payoutFinanceSummary(
        receivedCents: received + 1,
        payouts: payouts,
        lessons: lessons,
      );
      expect(f['difference'], '0.01');
      expect(_issue(f, 'unreconciled')['amount'], '0.01');
    });

    test('a refund on a lesson that was not cancelled is unallocated', () {
      final f = payoutFinanceSummary(
        receivedCents: 17500,
        payouts: const PayoutTotals(),
        lessons: [_lesson(1, refundStatus: 'Approved', refund: 5000)],
      );
      expect(f['refunded'], '50.00');
      expect(f['unallocated'], '125.00');
      expect(f['awaitingPayoutGeneration'], '0.00');
      expect(f['reconciled'], isTrue);
      expect(_issue(f, 'refund_on_active_lesson')['amount'], '125.00');
    });

    test('missing and backfilled commission rates are identified', () {
      final f = payoutFinanceSummary(
        receivedCents: 35000,
        payouts: const PayoutTotals(),
        lessons: [
          _lesson(1, rate: null, source: null),
          _lesson(2, source: 'Backfilled'),
        ],
      );
      expect(f['awaitingPayoutGeneration'], '350.00');
      expect((f['counts']! as Map)['eligibleLessons'], 1);
      expect(_issue(f, 'missing_commission_rate')['count'], 1);
      expect(_issue(f, 'backfilled_commission_rate')['count'], 1);
      expect(_issue(f, 'backfilled_commission_rate')['severity'], 'info');
    });

    test('payouts whose amounts do not add up are flagged', () {
      final f = payoutFinanceSummary(
        receivedCents: 17500,
        payouts: const PayoutTotals(
          pendingCount: 1,
          pendingNetCents: 15000,
          commissionCents: 1750,
          inconsistentCount: 1,
        ),
        lessons: [_lesson(7, payoutId: 70, payoutTotal: 16750)],
      );
      expect(
        _codes(f),
        containsAll([
          'payout_amount_differs',
          'payout_amounts_inconsistent',
          'unreconciled',
        ]),
      );
    });

    test('a payout on a cancelled lesson is flagged', () {
      final f = payoutFinanceSummary(
        receivedCents: 17500,
        payouts: const PayoutTotals(
          pendingCount: 1,
          pendingNetCents: 15750,
          commissionCents: 1750,
        ),
        lessons: [_lesson(7, status: 'Cancelled', payoutId: 70)],
      );
      expect(_codes(f), ['payout_on_cancelled_lesson']);
    });

    test('nothing paid: everything is zero and reconciled', () {
      final f = payoutFinanceSummary(
        receivedCents: 0,
        payouts: const PayoutTotals(),
        lessons: const [],
      );
      expect(f['moneyReceived'], '0.00');
      expect(f['reconciled'], isTrue);
      expect(f['issues'], isEmpty);
    });
  });

  group('cancellations and unfinished lessons', () {
    Map<String, Object?> summarise(List<PaidLesson> lessons) =>
        payoutFinanceSummary(
          receivedCents: lessons.fold(0, (sum, l) => sum + l.priceCents),
          payouts: const PayoutTotals(),
          lessons: lessons,
        );

    test('a cancelled paid lesson without a refund record is flagged, not '
        'counted as retained revenue', () {
      final f = summarise([
        _lesson(1, status: 'Cancelled', ended: false),
      ]);
      expect(f['retainedCancellationRevenue'], '0.00');
      expect(f['unallocated'], '175.00');
      expect(f['reconciled'], isTrue); // accounted for, but flagged
      expect(_issue(f, 'cancelled_without_refund_record')['count'], 1);
      expect(_issue(f, 'cancelled_without_refund_record')['amount'], '175.00');
      expect(
        payoutIneligibility(_lesson(1, status: 'Cancelled')),
        'cancelled',
      );
    });

    test('full retention and partial refunds: each rand counted once', () {
      // R175 each: 0% approved, 50% approved, rejected.
      final f = summarise([
        _lesson(1, status: 'Cancelled', refundStatus: 'Approved', refund: 0),
        _lesson(2, status: 'Cancelled', refundStatus: 'Approved', refund: 8750),
        _lesson(3, status: 'Cancelled', refundStatus: 'Rejected'),
      ]);
      expect(f['refunded'], '87.50');
      expect(f['retainedCancellationRevenue'], '437.50'); // 175+87.50+175
      expect(f['awaitingRefundDecision'], '0.00');
      expect(f['accountedFor'], '525.00');
      expect(f['reconciled'], isTrue);
      expect(f['issues'], isEmpty);
    });

    test('tutor-initiated cancellations (100% refund) follow the same rules',
        () {
      // Pending until decided; approved = fully refunded; an admin who
      // rejects it leaves the price as retained (the line is "Retained from
      // cancellations", not only late student cancellations).
      const full = 17500;
      expect(
        summarise([
          _lesson(
            1,
            status: 'Cancelled',
            refundStatus: 'Pending',
            refund: full,
          ),
        ])['awaitingRefundDecision'],
        '175.00',
      );
      final approved = summarise([
        _lesson(1, status: 'Cancelled', refundStatus: 'Approved', refund: full),
      ]);
      expect(approved['refunded'], '175.00');
      expect(approved['retainedCancellationRevenue'], '0.00');
      final rejected = summarise([
        _lesson(1, status: 'Cancelled', refundStatus: 'Rejected'),
      ]);
      expect(rejected['retainedCancellationRevenue'], '175.00');
      expect(rejected['refunded'], '0.00');
    });

    test('a paid lesson still Postponed after its end is flagged and never '
        'paid out', () {
      final lesson = _lesson(
        1,
        status: 'Postponed',
        ended: false, // only Completed / Confirmed+ended count as finished
        pastEnd: true,
      );
      expect(payoutIneligibility(lesson), 'not_finished');
      final f = summarise([lesson]);
      expect(f['heldForUpcomingLessons'], '0.00');
      expect(f['awaitingPayoutGeneration'], '0.00');
      expect(f['unallocated'], '175.00');
      expect(_issue(f, 'postponed_past_end')['count'], 1);
      // Before its end time it is simply upcoming.
      final upcoming = summarise([
        _lesson(2, status: 'Postponed', ended: false),
      ]);
      expect(upcoming['heldForUpcomingLessons'], '175.00');
      expect(upcoming['issues'], isEmpty);
    });

    test('other unconfirmed paid lessons past their end are flagged too', () {
      final f = summarise([
        _lesson(1, status: 'Accepted', ended: false, pastEnd: true),
      ]);
      expect(_codes(f), ['unconfirmed_past_end']);
      expect(f['unallocated'], '175.00');
    });

    test('unresolved commission history is visible before the lesson ends',
        () {
      final f = summarise([
        _lesson(1, ended: false, rate: null, source: null),
      ]);
      expect(f['heldForUpcomingLessons'], '175.00');
      expect(_issue(f, 'missing_commission_rate')['count'], 1);
      expect(
        payoutIneligibility(_lesson(1, rate: null, source: null)),
        'missing_rate',
      );
      // A manually resolved rate is used like any other.
      expect(
        draftPayout(_lesson(1, source: 'Manual')).netCents,
        15750,
      );
    });
  });

  group('refunds blocking approval and payment', () {
    test('pending, approved and processed refunds block; rejected does not',
        () {
      expect(payoutRefundBlock(null), isNull);
      expect(payoutRefundBlock('Rejected'), isNull);
      expect(payoutRefundBlock('Pending'), contains('awaiting a decision'));
      expect(payoutRefundBlock('Approved'), contains('refund was approved'));
      expect(payoutRefundBlock('Processed'), contains('refund was processed'));
    });
  });

  group('payment reference', () {
    test('optional, trimmed, at most 100 characters', () {
      expect(normalisePaymentReference(null), isNull);
      expect(normalisePaymentReference('   '), isNull);
      expect(normalisePaymentReference(' EFT-2026-001 '), 'EFT-2026-001');
      expect(normalisePaymentReference('x' * 100), hasLength(100));
      expect(
        () => normalisePaymentReference('x' * 101),
        throwsFormatException,
      );
    });

    test('must be single-line text', () {
      expect(() => normalisePaymentReference(42), throwsFormatException);
      expect(
        () => normalisePaymentReference('line one\nline two'),
        throwsFormatException,
      );
    });
  });
}
