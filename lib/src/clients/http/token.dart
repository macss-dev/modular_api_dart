/// Session management for in-memory access token storage.
///
/// This class keeps the access token and its expiration date in memory
/// during the application lifetime. It is NOT persisted to disk.
class Token {
  /// Current access token (JWT). Null if not authenticated.
  static String? accessToken;

  /// Expiration date/time of the current access token.
  /// Optional - used for proactive refresh strategies.
  static DateTime? accessExp;

  /// Clears the session data (logout).
  static void clear() {
    accessToken = null;
    accessExp = null;
  }

  /// Checks if the session has an active access token.
  static bool get isAuthenticated => accessToken != null;

  /// Checks if the access token is expired (if accessExp is available).
  static bool get isExpired {
    if (accessExp == null) return false;
    return DateTime.now().isAfter(accessExp!);
  }
}
