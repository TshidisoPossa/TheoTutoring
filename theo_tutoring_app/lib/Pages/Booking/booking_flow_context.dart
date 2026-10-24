import '../../models/tutor.dart';

class BookingFlowContext {
  BookingFlowContext({
    required this.tutor,
    required this.subject,
    this.studentName,
    this.studentPhoto,
  }) : selection = TutorSelection(
         tutorId: tutor.tutorId,
         subjectId: subject.subjectId,
       );

  final Tutor tutor;
  final TutorSubject subject;
  final TutorSelection selection;

  /// The signed-in student, shown in the booking pages' top bar.
  final String? studentName;
  final String? studentPhoto;
}
