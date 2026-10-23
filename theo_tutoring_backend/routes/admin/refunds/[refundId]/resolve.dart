import 'package:dart_frog/dart_frog.dart';
import 'approve.dart';

export 'approve.dart' show handleRefundAction;

Future<Response> onRequest(RequestContext context, String refundId) =>
    handleRefundAction(context, action: 'resolve', refundId: refundId);
