class ApiEndpoints {
  static const signup = '/auth/signup';
  static const login = '/auth/login';
  /// Caregiver: Firestore `caregivers/{username}` holds `password`; backend also issues a JWT.
  static const caregiverSignup = '/auth/caregiver/signup';
  static const caregiverLogin = '/auth/caregiver/login';
  static const upsertUser = '/users';
  static String getUser(int id) => '/users/$id';
  static const linkCaregiver = '/caregivers/link';
  static const medications = '/medications';
  static String medicationsForUser(int userId) => '/medications/$userId';
  static const confirmDose = '/dose/confirm';
  static String doseHistory(int userId) => '/dose/history/$userId';
  static String insights(int userId) => '/insights/$userId';
  static String aiSuggestion(int userId) => '/ai-suggestion/$userId';
  static const caregiverAlert = '/caregiver/alert';
  static const scanMedication = '/scan-medication';

  /// Dev-only: backend endpoint that triggers a real push (FCM/APNs).
  /// Implement this on your server/Cloud Function.
  static const devPush = '/dev/push';

  static const registerPushToken = '/push/token';
}

