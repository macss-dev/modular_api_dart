import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Helper class for JWT token generation and validation.
///
/// Provides methods to create access tokens and refresh tokens
/// for the authentication system.
class JwtHelper {
  /// JWT secret key from environment variable.
  ///
  /// IMPORTANT: In production, use a strong secret key stored securely.
  /// Generate a secure key with: `openssl rand -base64 32`
  static final String _secret = Platform.environment['JWT_SECRET'] ??
      'dev-secret-key-change-in-production';

  /// Access token expiration time in seconds (15 minutes).
  static const int _accessTokenExpirationSeconds = 15 * 60;

  /// Refresh token expiration time in seconds (7 days).
  static const int _refreshTokenExpirationSeconds = 7 * 24 * 60 * 60;

  /// Generates an access token for a user.
  ///
  /// [userId] - User ID
  /// [username] - Username
  ///
  /// Returns a signed JWT access token.
  static String generateAccessToken({
    required int userId,
    required String username,
  }) {
    final now = DateTime.now();
    final expiresAt = now.add(Duration(seconds: _accessTokenExpirationSeconds));

    final jwt = JWT(
      {
        'sub': userId.toString(), // Subject (user ID)
        'username': username,
        'type': 'access',
        'iat': now.millisecondsSinceEpoch ~/ 1000, // Issued at
        'exp': expiresAt.millisecondsSinceEpoch ~/ 1000, // Expires at
      },
    );

    return jwt.sign(SecretKey(_secret));
  }

  /// Generates a refresh token for a user.
  ///
  /// [userId] - User ID
  /// [tokenId] - Unique token ID (from database)
  ///
  /// Returns a signed JWT refresh token.
  static String generateRefreshToken({
    required int userId,
    required int tokenId,
  }) {
    final now = DateTime.now();
    final expiresAt =
        now.add(Duration(seconds: _refreshTokenExpirationSeconds));

    final jwt = JWT(
      {
        'sub': userId.toString(), // Subject (user ID)
        'jti': tokenId.toString(), // JWT ID (token record ID in database)
        'type': 'refresh',
        'iat': now.millisecondsSinceEpoch ~/ 1000, // Issued at
        'exp': expiresAt.millisecondsSinceEpoch ~/ 1000, // Expires at
      },
    );

    return jwt.sign(SecretKey(_secret));
  }

  /// Verifies and decodes a JWT token.
  ///
  /// [token] - JWT token to verify
  ///
  /// Returns the decoded payload if valid, throws [JWTException] otherwise.
  static Map<String, dynamic> verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_secret));
      return jwt.payload as Map<String, dynamic>;
    } on JWTExpiredException {
      throw JwtException('Token has expired');
    } on JWTException catch (e) {
      throw JwtException('Invalid token: ${e.message}');
    }
  }

  /// Calculates the expiration DateTime for a refresh token.
  ///
  /// Used when storing refresh tokens in the database.
  static DateTime calculateRefreshTokenExpiration() {
    return DateTime.now().add(
      Duration(seconds: _refreshTokenExpirationSeconds),
    );
  }

  /// Calculates the expiration time in seconds for access tokens.
  ///
  /// Used in the response to inform clients when to refresh.
  static int get accessTokenExpiresIn => _accessTokenExpirationSeconds;
}

/// Custom exception for JWT-related errors.
class JwtException implements Exception {
  final String message;

  JwtException(this.message);

  @override
  String toString() => 'JwtException: $message';
}
