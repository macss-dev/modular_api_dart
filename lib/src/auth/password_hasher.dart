import 'package:bcrypt/bcrypt.dart';

/// Utility class for password hashing and verification using bcrypt.
///
/// Bcrypt is a secure password hashing function designed to be slow
/// and resistant to brute-force attacks.
///
/// Usage:
/// ```dart
/// // Hash a password
/// final hash = PasswordHasher.hash('abc123');
///
/// // Verify a password
/// final isValid = PasswordHasher.verify('abc123', hash);
/// ```
class PasswordHasher {
  /// Default bcrypt cost factor (higher = more secure but slower).
  /// Recommended range: 10-14
  static const int defaultCost = 12;

  /// Hashes a password using bcrypt.
  ///
  /// [password] - Plain text password to hash
  /// [cost] - Work factor (default: 12). Higher values are more secure but slower.
  ///
  /// Returns the bcrypt hash string.
  static String hash(String password, {int cost = defaultCost}) {
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: cost));
  }

  /// Verifies a password against a bcrypt hash.
  ///
  /// [password] - Plain text password to verify
  /// [hash] - Bcrypt hash to compare against
  ///
  /// Returns true if the password matches the hash, false otherwise.
  static bool verify(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (e) {
      // Invalid hash format or other error
      return false;
    }
  }

  /// Checks if a hash needs rehashing (if cost factor has changed).
  ///
  /// Useful for upgrading password security over time.
  static bool needsRehash(String hash, {int targetCost = defaultCost}) {
    try {
      // Extract cost from hash (format: $2b$cost$...)
      final parts = hash.split('\$');
      if (parts.length < 4) return true;

      final currentCost = int.tryParse(parts[2]);
      if (currentCost == null) return true;

      return currentCost < targetCost;
    } catch (e) {
      return true;
    }
  }
}
