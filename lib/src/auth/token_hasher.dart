import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Utility for securely hashing tokens using SHA-256.
///
/// This class provides static helpers to hash tokens (for example refresh tokens)
/// before persisting them to the database. Storing token hashes instead of raw
/// tokens is a recommended security practice.
///
/// Example:
/// ```dart
/// // Hash a refresh token before saving it to the DB
/// final refreshToken = JwtHelper.generateRefreshToken(...);
/// final hash = TokenHasher.hash(refreshToken);
/// await db.execute('INSERT INTO tokens (hash) VALUES (@hash)', {'hash': hash});
///
/// // Verify an incoming token against a stored hash
/// final incomingToken = request.body['refresh_token'];
/// final incomingHash = TokenHasher.hash(incomingToken);
/// final stored = await db.query('SELECT * FROM tokens WHERE hash = @hash', {'hash': incomingHash});
/// ```
class TokenHasher {
  /// Hashes a token using SHA-256.
  ///
  /// Parameters:
  /// - [token]: The token to hash (e.g. a JWT refresh token).
  ///
  /// Returns:
  /// - String: The SHA-256 hash of the token as a hexadecimal string (64 chars).
  ///
  /// Example:
  /// ```dart
  /// final token = 'eyJhbGciOiJIUzI1NiIs...';
  /// final hash = TokenHasher.hash(token);
  /// // hash = 'a1b2c3d4e5f6...' (64 char hex)
  /// ```
  static String hash(String token) {
    final bytes = utf8.encode(token);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verifies whether a token matches a stored hash.
  ///
  /// Convenience method that hashes [token] and compares it with [expectedHash].
  ///
  /// Parameters:
  /// - [token]: The token to verify.
  /// - [expectedHash]: The stored hash to compare against.
  ///
  /// Returns:
  /// - bool: true if the token's hash equals the expected hash.
  ///
  /// Example:
  /// ```dart
  /// final token = getTokenFromRequest();
  /// final storedHash = getHashFromDatabase();
  ///
  /// if (TokenHasher.verify(token, storedHash)) {
  ///   print('Token valid');
  /// } else {
  ///   print('Token invalid');
  /// }
  /// ```
  static bool verify(String token, String expectedHash) {
    final tokenHash = hash(token);
    return tokenHash == expectedHash;
  }
}
