// Money rules for the admin Payouts page: which paid lessons earn a tutor
// payout, what that payout is, and where every rand a student paid has gone.
//
// Pure Dart on integer cents (no floating point, no database), so the rules
// are unit-tested directly (test/payout_finance_test.dart). The repository
// (lib/admin_payouts.dart) loads the rows and stores the results.
//
// Definitions (each paid lesson's money is counted in exactly one place):
//
//   moneyReceived        every successful student payment: purchasepayment
//                        rows, plus successful legacy per-booking payment rows
//                        (bookings without a purchase). Refunds are NOT
//                        subtracted here; they are their own line.
//   refunded             approved or processed refund amounts.
//   retainedCancellationRevenue
//                        a cancelled (or rejected) lesson's price minus its
//                        approved/processed refund, once the refund is decided
//                        (a rejected refund keeps the whole price). Student-
//                        and tutor-initiated cancellations alike. This is
//                        TheoTutoring's, but it is NOT lesson commission.
//                        Every app path that cancels a paid lesson records a
//                        refund (0-100%), so a cancelled paid lesson WITHOUT a
//                        refund record is not counted here: it is unallocated
//                        and flagged (cancelled_without_refund_record).
//   awaitingRefundDecision
//                        lessons whose refund is still Pending: the money is
//                        held until an administrator decides.
//   heldForUpcomingLessons
//                        paid lessons that have not finished yet.
//   awaitingPayoutGeneration
//                        finished, eligible lessons with no payout record yet
//                        (run "Generate eligible payouts").
//   platformCommission   CommissionAmount on payout records (any status): the
//                        purchase's captured rate applied to the lesson price.
//   owedToTutors         NetAmount of Pending and Approved payouts.
//   paidToTutors         NetAmount of Paid payouts.
//   unallocated          money that fits none of the rules above, always
//                        flagged: a refund on a lesson that was not
//                        cancelled, a cancelled lesson with no refund record,
//                        or a lesson still Postponed (or otherwise not
//                        Confirmed) after its end time, for which there is no
//                        completion rule and so no payout.
//
// moneyReceived = refunded + retained + awaitingRefundDecision + held
//               + awaitingPayoutGeneration + commission + owed + paid
//               + unallocated
// whenever the records are consistent. Any difference is reported, never
// hidden (legacy rows, a refund approved after a payout, edited amounts).

// ignore_for_file: public_member_api_docs

/// "123.45", "123.4", "123", "-5.00" -> cents. Null for null or invalid text.
/// MySQL DECIMAL values arrive as text, so money never passes through a
/// double.
int? parseCents(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2})\d*)?$').firstMatch(text);
  if (match == null) return null;
  final cents =
      int.parse(match.group(2)!) * 100 +
      int.parse((match.group(3) ?? '0').padRight(2, '0'));
  return match.group(1) == '-' ? -cents : cents;
}

/// A percentage with two decimals ("10.00", "12.5") in hundredths of a
/// percent: 1000 = 10.00%.
int? parseRateHundredths(String? value) => parseCents(value);

/// Cents -> "1234.50" / "-12.05", the form DECIMAL columns and the API use.
String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// The commission on [priceCents] at [rateHundredths] (1000 = 10%), rounded
/// half up to the cent: R175.00 at 10% -> R17.50; R0.05 at 10% -> R0.01.
int commissionCents(int priceCents, int rateHundredths) {
  if (priceCents < 0 || rateHundredths < 0 || rateHundredths > 10000) {
    throw ArgumentError('Invalid price or commission rate.');
  }
  return (priceCents * rateHundredths + 5000) ~/ 10000;
}

/// Booking statuses that mean the lesson will not take place.
const cancelledBookingStatuses = {'Cancelled', 'Rejected'};

/// Refund statuses that mean the money went back to the student.
const settledRefundStatuses = {'Approved', 'Processed'};

/// One paid lesson as the repository loads it.
class PaidLesson {
  const PaidLesson({
    required this.bookingId,
    required this.tutorId,
    required this.bookingStatus,
    required this.ended,
    required this.priceCents,
    this.pastEnd = false,
    this.commissionRateHundredths,
    this.commissionSource,
    this.refundStatus,
    this.refundCents,
    this.payoutId,
    this.payoutTotalCents,
  });

  final int bookingId;
  final int tutorId;
  final String bookingStatus;

  /// Completed, or Confirmed and past its end time in South African time
  /// (the same rule as the tutor's Schedule and student reviews).
  final bool ended;

  /// The scheduled end time has passed (South African time), whatever the
  /// status. A lesson past its end but not [ended] (e.g. still Postponed) has
  /// no completion rule: it is flagged, never paid out.
  final bool pastEnd;

  /// The lesson's share of what the student paid (its LessonPriceAtPurchase,
  /// or a legacy payment's Amount).
  final int priceCents;

  /// The purchase's captured commission rate; null when none was recorded.
  final int? commissionRateHundredths;

  /// 'Purchase' (captured when the student bought), 'Backfilled' (set by
  /// migration 013 for purchases made before the snapshot existed) or
  /// 'Payment' (a legacy payment row's own rate).
  final String? commissionSource;

  /// The lesson's refund row, if any: Pending, Approved, Rejected, Processed.
  final String? refundStatus;
  final int? refundCents;

  /// The lesson's payout record, if one was generated.
  final int? payoutId;

  /// That payout's CommissionAmount + NetAmount.
  final int? payoutTotalCents;

  bool get cancelled => cancelledBookingStatuses.contains(bookingStatus);
  bool get refundSettled => settledRefundStatuses.contains(refundStatus);
  bool get refundPending => refundStatus == 'Pending';
  int get settledRefundCents => refundSettled ? (refundCents ?? 0) : 0;
}

/// Why a lesson does not (yet) get a payout; null when it is eligible.
String? payoutIneligibility(PaidLesson lesson) {
  if (lesson.payoutId != null) return 'already_generated';
  if (lesson.cancelled) return 'cancelled';
  if (!lesson.ended) return 'not_finished';
  // A refund that is pending, approved or processed blocks the payout; only
  // a rejected refund (the student keeps nothing back) allows it.
  if (lesson.refundStatus != null && lesson.refundStatus != 'Rejected') {
    return 'refund';
  }
  if (lesson.commissionRateHundredths == null) return 'missing_rate';
  return null;
}

bool isEligibleForPayout(PaidLesson lesson) =>
    payoutIneligibility(lesson) == null;

/// Why an outstanding payout may not be approved or marked paid because of
/// its lesson's refund; null when nothing blocks it. A Pending, Approved or
/// Processed refund blocks until resolved; a Rejected refund never does.
/// Paid payouts are never reversed automatically.
String? payoutRefundBlock(String? refundStatus) => switch (refundStatus) {
  'Pending' =>
    'A refund for this lesson is awaiting a decision. Decide it before '
        'approving or paying this payout.',
  'Approved' || 'Processed' =>
    'A refund was ${refundStatus!.toLowerCase()} for this lesson after the '
        'payout was generated. Resolve it before approving or paying this '
        'payout.',
  _ => null,
};

/// A payout record to insert for an eligible lesson.
class PayoutDraft {
  const PayoutDraft({
    required this.bookingId,
    required this.tutorId,
    required this.amountCents,
    required this.commissionCents,
    required this.netCents,
  });

  final int bookingId;
  final int tutorId;
  final int amountCents;
  final int commissionCents;
  final int netCents;
}

/// The payout for an eligible [lesson]: its price, less the purchase's
/// captured commission. Throws [StateError] for an ineligible lesson.
PayoutDraft draftPayout(PaidLesson lesson) {
  final reason = payoutIneligibility(lesson);
  if (reason != null) {
    throw StateError('Booking ${lesson.bookingId} is not eligible: $reason');
  }
  final commission = commissionCents(
    lesson.priceCents,
    lesson.commissionRateHundredths!,
  );
  return PayoutDraft(
    bookingId: lesson.bookingId,
    tutorId: lesson.tutorId,
    amountCents: lesson.priceCents,
    commissionCents: commission,
    netCents: lesson.priceCents - commission,
  );
}

/// Totals over every payout record, by status.
class PayoutTotals {
  const PayoutTotals({
    this.pendingCount = 0,
    this.pendingNetCents = 0,
    this.approvedCount = 0,
    this.approvedNetCents = 0,
    this.paidCount = 0,
    this.paidNetCents = 0,
    this.commissionCents = 0,
    this.inconsistentCount = 0,
  });

  final int pendingCount;
  final int pendingNetCents;
  final int approvedCount;
  final int approvedNetCents;
  final int paidCount;
  final int paidNetCents;

  /// CommissionAmount over every payout, whatever its status.
  final int commissionCents;

  /// Payouts whose Amount is not CommissionAmount + NetAmount.
  final int inconsistentCount;

  int get owedCents => pendingNetCents + approvedNetCents;
}

class _Issue {
  _Issue(this.code, this.severity, this.message);
  final String code;
  final String severity;
  final String message;
  int count = 0;
  int cents = 0;

  Map<String, Object?> toJson({bool withAmount = true}) => {
    'code': code,
    'severity': severity,
    'count': count,
    'amount': withAmount ? formatCents(cents) : null,
    'message': message,
  };
}

/// The Payouts page's financial overview and reconciliation (see the
/// definitions at the top of this file). Amounts are "1234.50" strings.
Map<String, Object?> payoutFinanceSummary({
  required int receivedCents,
  required PayoutTotals payouts,
  required List<PaidLesson> lessons,
}) {
  var refunded = 0;
  var retained = 0;
  var awaitingRefund = 0;
  var held = 0;
  var awaitingGeneration = 0;
  var unallocated = 0;
  var linkedPayoutCents = 0;
  var eligibleCount = 0;
  var awaitingGenerationCount = 0;
  var heldCount = 0;
  var backfilledCount = 0;

  final refundAfterPayout = _Issue(
    'refund_after_payout',
    'warning',
    'A refund was approved for a lesson that already has a payout. The '
        'payout was not changed; review it before paying (or recover the '
        'amount if it was already paid).',
  );
  final refundRequestedAfterPayout = _Issue(
    'refund_pending_after_payout',
    'warning',
    'A refund is awaiting a decision for a lesson that already has a payout.',
  );
  final payoutOnCancelled = _Issue(
    'payout_on_cancelled_lesson',
    'warning',
    'A cancelled lesson has a payout record.',
  );
  final payoutAmountDiffers = _Issue(
    'payout_amount_differs',
    'warning',
    "A payout's commission and net do not add up to the lesson price.",
  );
  final refundOnActiveLesson = _Issue(
    'refund_on_active_lesson',
    'warning',
    'A refund was approved for a lesson that was not cancelled; the rest of '
        'its price is shown as unallocated and no payout is generated.',
  );
  final cancelledWithoutRefund = _Issue(
    'cancelled_without_refund_record',
    'warning',
    'A paid lesson was cancelled but has no refund record (every cancellation '
        'in the app creates one). Its money is shown as unallocated, not as '
        'retained revenue, until the refund is recorded.',
  );
  final postponedPastEnd = _Issue(
    'postponed_past_end',
    'warning',
    'A paid lesson is still Postponed after its scheduled end time. There is '
        'no rule for whether it took place, so no payout is generated; '
        'confirm or cancel it.',
  );
  final unconfirmedPastEnd = _Issue(
    'unconfirmed_past_end',
    'warning',
    'A paid lesson is past its end time but neither Confirmed nor Completed, '
        'so no payout is generated; review its status.',
  );
  final missingRate = _Issue(
    'missing_commission_rate',
    'warning',
    'Paid lessons whose purchase has no commission rate recorded (history '
        'migration 013 could not establish). No payout is generated for them '
        'until an administrator records the rate.',
  );
  final inconsistentPayouts = _Issue(
    'payout_amounts_inconsistent',
    'warning',
    'Payout records whose gross amount is not commission plus net.',
  );

  for (final lesson in lessons) {
    refunded += lesson.settledRefundCents;
    if (lesson.commissionSource == 'Backfilled') backfilledCount += 1;

    if (lesson.payoutId != null) {
      // Its money is in the payout lines (commission + owed/paid).
      linkedPayoutCents += lesson.payoutTotalCents ?? 0;
      if (lesson.refundSettled) {
        refundAfterPayout
          ..count += 1
          ..cents += lesson.settledRefundCents;
      } else if (lesson.refundPending) {
        refundRequestedAfterPayout
          ..count += 1
          ..cents += lesson.refundCents ?? 0;
      }
      if (lesson.cancelled) {
        payoutOnCancelled
          ..count += 1
          ..cents += lesson.payoutTotalCents ?? 0;
      }
      if (lesson.payoutTotalCents != lesson.priceCents) {
        payoutAmountDiffers
          ..count += 1
          ..cents += (lesson.payoutTotalCents ?? 0) - lesson.priceCents;
      }
      continue;
    }

    if (lesson.cancelled) {
      if (lesson.refundStatus == null) {
        cancelledWithoutRefund
          ..count += 1
          ..cents += lesson.priceCents;
        unallocated += lesson.priceCents;
      } else if (lesson.refundPending) {
        awaitingRefund += lesson.priceCents;
      } else {
        retained += lesson.priceCents - lesson.settledRefundCents;
      }
      continue;
    }

    // Unresolved commission history stays visible whatever the lesson's
    // state, not only once it has finished.
    if (lesson.commissionRateHundredths == null) {
      missingRate
        ..count += 1
        ..cents += lesson.priceCents;
    }

    if (lesson.refundSettled) {
      refundOnActiveLesson
        ..count += 1
        ..cents += lesson.priceCents - lesson.settledRefundCents;
      unallocated += lesson.priceCents - lesson.settledRefundCents;
    } else if (lesson.refundPending) {
      awaitingRefund += lesson.priceCents;
    } else if (!lesson.ended && lesson.pastEnd) {
      (lesson.bookingStatus == 'Postponed'
          ? postponedPastEnd
          : unconfirmedPastEnd)
        ..count += 1
        ..cents += lesson.priceCents;
      unallocated += lesson.priceCents;
    } else if (lesson.ended) {
      awaitingGeneration += lesson.priceCents;
      awaitingGenerationCount += 1;
      if (isEligibleForPayout(lesson)) eligibleCount += 1;
    } else {
      held += lesson.priceCents;
      heldCount += 1;
    }
  }

  final payoutCents =
      payouts.commissionCents + payouts.owedCents + payouts.paidNetCents;
  if (payouts.inconsistentCount > 0) {
    inconsistentPayouts.count = payouts.inconsistentCount;
  }

  final allocated =
      refunded +
      retained +
      awaitingRefund +
      held +
      awaitingGeneration +
      unallocated +
      payoutCents;
  final difference = receivedCents - allocated;

  final issues = <Map<String, Object?>>[
    for (final issue in [
      refundAfterPayout,
      refundRequestedAfterPayout,
      payoutOnCancelled,
      payoutAmountDiffers,
      refundOnActiveLesson,
      cancelledWithoutRefund,
      postponedPastEnd,
      unconfirmedPastEnd,
      missingRate,
    ])
      if (issue.count > 0) issue.toJson(),
    if (inconsistentPayouts.count > 0)
      inconsistentPayouts.toJson(withAmount: false),
    if (payoutCents != linkedPayoutCents)
      {
        'code': 'payout_without_paid_lesson',
        'severity': 'warning',
        'count': null,
        'amount': formatCents(payoutCents - linkedPayoutCents),
        'message':
            'Payout records that are not linked to a successfully paid '
            'lesson.',
      },
    if (difference != 0)
      {
        'code': 'unreconciled',
        'severity': 'warning',
        'count': null,
        'amount': formatCents(difference),
        'message':
            'Money received does not equal the money accounted for. The '
            'difference is shown as it is, not adjusted.',
      },
    if (backfilledCount > 0)
      {
        'code': 'backfilled_commission_rate',
        'severity': 'info',
        'count': backfilledCount,
        'amount': null,
        'message':
            'Lessons from purchases made before commission was captured at '
            'purchase time use the rate migration 013 established from the '
            'settings history (marked Backfilled).',
      },
  ];

  return {
    'moneyReceived': formatCents(receivedCents),
    'platformCommission': formatCents(payouts.commissionCents),
    'owedToTutors': formatCents(payouts.owedCents),
    'paidToTutors': formatCents(payouts.paidNetCents),
    'refunded': formatCents(refunded),
    'heldForUpcomingLessons': formatCents(held),
    'retainedCancellationRevenue': formatCents(retained),
    'awaitingRefundDecision': formatCents(awaitingRefund),
    'awaitingPayoutGeneration': formatCents(awaitingGeneration),
    'unallocated': formatCents(unallocated),
    'accountedFor': formatCents(allocated),
    'difference': formatCents(difference),
    'reconciled': difference == 0,
    'counts': {
      'eligibleLessons': eligibleCount,
      'awaitingPayoutGeneration': awaitingGenerationCount,
      'upcomingLessons': heldCount,
      'pendingPayouts': payouts.pendingCount,
      'approvedPayouts': payouts.approvedCount,
      'paidPayouts': payouts.paidCount,
    },
    'issues': issues,
  };
}

/// The optional external payment reference for "Mark as paid": trimmed,
/// 1-100 characters, no control characters. Null when absent or blank.
/// Throws [FormatException] with a message for the administrator.
String? normalisePaymentReference(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('The payment reference must be text.');
  }
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.length > maxPaymentReferenceLength) {
    throw const FormatException(
      'The payment reference must be $maxPaymentReferenceLength characters '
      'or fewer.',
    );
  }
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(text)) {
    throw const FormatException(
      'The payment reference cannot contain line breaks or control '
      'characters.',
    );
  }
  return text;
}

const maxPaymentReferenceLength = 100;
