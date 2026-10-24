// Holds who is calling: passed from the middleware to every /tutor route
class TutorSession {
  const TutorSession(
    this.userId,
    this.tutorId, {
    this.accountStatus = 'Active',
  });
  final String userId; // Firebase UID (User.FirebaseUid)
  final int tutorId; // TutorProfile.TutorID
  final String accountStatus; // User.AccountStatus ('Active' or 'Pending')

  bool get isActive => accountStatus.trim().toLowerCase() == 'active';
}
