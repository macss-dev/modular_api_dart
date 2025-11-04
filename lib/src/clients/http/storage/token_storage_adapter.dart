/// Platform-agnostic interface for storing refresh tokens.
///
/// Allows multiple implementations:
/// - [MemoryStorageAdapter]: In-memory storage (tests, temporary)
/// - [FileStorageAdapter]: Encrypted file storage with AES-GCM (CLI, server, desktop)
/// - FlutterSecureStorageAdapter: Keychain/KeyStore (Flutter apps - implement in the app)
abstract interface class TokenStorageAdapter {
  /// Saves a refresh token for the specified user.
  ///
  /// [userId] - Unique identifier for the user (username, email or ID)
  /// [token] - The refresh token to store securely
  Future<void> saveRefresh(String userId, String token);

  /// Reads the refresh token for the specified user.
  ///
  /// Returns `null` if the token is not found.
  Future<String?> readRefresh(String userId);

  /// Deletes the refresh token for the specified user.
  ///
  /// Should be called on logout or when the refresh token is invalidated.
  Future<void> deleteRefresh(String userId);

  /// Deletes all stored refresh tokens.
  ///
  /// Useful for full logout of all users.
  Future<void> deleteAll();
}

/// Unified exception for token storage errors.
///
/// Thrown when there are problems saving, reading or deleting tokens.
final class TokenStorageException implements Exception {
  /// Creates a storage exception.
  ///
  /// [message] - Error description
  /// [cause] - Original exception that caused this error (optional)
  /// [stackTrace] - Stack trace of the original error (optional)
  const TokenStorageException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  /// Descriptive message for the error
  final String message;

  /// Original exception that caused this error (if any)
  final Object? cause;

  /// Stack trace of the original exception (if any)
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('TokenStorageException: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}
