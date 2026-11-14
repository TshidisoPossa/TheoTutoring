import 'package:dart_frog/dart_frog.dart';
import 'approve.dart';

export 'approve.dart' show handlePayoutAction;

/// POST /admin/payouts/<id>/mark-paid: Approved -> Paid. Records the status
/// only; it does not transfer money.
Future<Response> onRequest(RequestContext context, String payoutId) =>
    handlePayoutAction(context, action: 'mark-paid', payoutId: payoutId);
