import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/refund_models.dart';

RefundCase _case({required String type, required String status}) =>
    RefundCase.fromJson({
      'id': type == 'report' ? 'report-12' : '12',
      'type': type,
      'status': status,
      'studentName': 'Student',
      'tutorName': 'Tutor',
      'amountPaid': 100,
    });

void main() {
  test('only an open paid cancellation can offer Override Decision', () {
    expect(_case(type: 'cancellation', status: 'pending').canOverride, isTrue);
    expect(_case(type: 'report', status: 'open').canOverride, isFalse);
    expect(_case(type: 'cancellation', status: 'approved').canOverride, isFalse);
  });
}
