import '../../models/tutor.dart';

class BookingFlowContext {
  BookingFlowContext({required this.tutor, required this.subject})
    : selection = TutorSelection(
        tutorId: tutor.tutorId,
        subjectId: subject.subjectId,
      );

  final Tutor tutor;
  final TutorSubject subject;
  final TutorSelection selection;
}
