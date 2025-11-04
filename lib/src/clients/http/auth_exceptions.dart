/// Exception thrown when authentication fails and re-login is required.
///
/// This exception is thrown when:
/// - A protected endpoint returns 401
/// - The refresh token attempt also fails with 401
/// - The user needs to log in again
///
/// The UI layer should catch this exception and navigate to the login screen.
class AuthReLoginException implements Exception {
  final String message;

  AuthReLoginException([this.message = 'Re-login required']);

  @override
  String toString() => 'AuthReLoginException: $message';
}
