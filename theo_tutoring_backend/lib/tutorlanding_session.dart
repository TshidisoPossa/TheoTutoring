// Holds who is calling: passed from the middleware to every /tutor route
class TutorSession {
  const TutorSession(this.userId, this.tutorId); // constructor
  final String userId; // Firebase UID (User.UserId)
  final int tutorId; // TutorProfile.TutorID
}
