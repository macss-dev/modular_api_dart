import 'package:modular_api/modular_api.dart';
import '../../db/postgres_client.dart';

/// Repository for authentication-related database operations.
///
/// Provides methods for user authentication, password verification,
/// and refresh token management.
class AuthRepository {
  final PostgresClient _db;

  AuthRepository(this._db);

  /// Retrieves a user by username.
  ///
  /// Returns a map with user data (id, username, full_name, created_at)
  /// or null if the user is not found.
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final results = await _db.query(
      '''
      SELECT id, username, full_name, created_at
      FROM auth.user
      WHERE username = @username
      ''',
      {'username': username},
    );

    return results.isEmpty ? null : results.first;
  }

  /// Retrieves a user by ID.
  Future<Map<String, dynamic>?> getUserById(int userId) async {
    final results = await _db.query(
      '''
      SELECT id, username, full_name, created_at
      FROM auth.user
      WHERE id = @userId
      ''',
      {'userId': userId},
    );

    return results.isEmpty ? null : results.first;
  }

  /// Verifies a user's password.
  ///
  /// [userId] - ID of the user
  /// [password] - Plain text password to verify
  ///
  /// Returns true if the password is correct, false otherwise.
  Future<bool> verifyPassword(int userId, String password) async {
    final results = await _db.query(
      '''
      SELECT password_hash
      FROM auth.password
      WHERE id_user = @userId
      ''',
      {'userId': userId},
    );

    if (results.isEmpty) {
      return false;
    }

    final storedHash = results.first['password_hash'] as String;
    return PasswordHasher.verify(password, storedHash);
  }

  /// Authenticates a user with username and password.
  ///
  /// Returns user data if authentication is successful, null otherwise.
  Future<Map<String, dynamic>?> authenticate(
    String username,
    String password,
  ) async {
    // Get user
    final user = await getUserByUsername(username);
    if (user == null) {
      return null;
    }

    // Verify password
    final userId = user['id'] as int;
    final isValid = await verifyPassword(userId, password);

    if (!isValid) {
      return null;
    }

    return user;
  }

  /// Saves a refresh token for a user.
  ///
  /// Returns the ID of the created refresh token record.
  Future<int> saveRefreshToken({
    required int userId,
    required String tokenHash,
    required DateTime expiresAt,
    int? previousId,
  }) async {
    final results = await _db.query(
      '''
      INSERT INTO auth.refresh_token (id_user, token_hash, expires_at, previous_id)
      VALUES (@userId, @tokenHash, @expiresAt, @previousId)
      RETURNING id
      ''',
      {
        'userId': userId,
        'tokenHash': tokenHash,
        'expiresAt': expiresAt.toIso8601String(),
        'previousId': previousId,
      },
    );

    return results.first['id'] as int;
  }

  /// Retrieves a refresh token by its hash.
  ///
  /// Returns token data or null if not found or revoked.
  Future<Map<String, dynamic>?> getRefreshToken(String tokenHash) async {
    final results = await _db.query(
      '''
      SELECT id, id_user, token_hash, revoked, expires_at, created_at
      FROM auth.refresh_token
      WHERE token_hash = @tokenHash
        AND revoked = false
      ''',
      {'tokenHash': tokenHash},
    );

    return results.isEmpty ? null : results.first;
  }

  /// Revokes a refresh token by its ID.
  Future<void> revokeRefreshToken(int tokenId) async {
    await _db.execute(
      '''
      UPDATE auth.refresh_token
      SET revoked = true
      WHERE id = @tokenId
      ''',
      {'tokenId': tokenId},
    );
  }

  /// Revokes all refresh tokens for a user.
  Future<void> revokeAllUserTokens(int userId) async {
    await _db.execute(
      '''
      UPDATE auth.refresh_token
      SET revoked = true
      WHERE id_user = @userId
        AND revoked = false
      ''',
      {'userId': userId},
    );
  }

  /// Updates a user's password.
  Future<void> updatePassword(int userId, String newPassword) async {
    final passwordHash = PasswordHasher.hash(newPassword);

    await _db.execute(
      '''
      UPDATE auth.password
      SET password_hash = @passwordHash,
          updated_at = CURRENT_TIMESTAMP
      WHERE id_user = @userId
      ''',
      {'userId': userId, 'passwordHash': passwordHash},
    );
  }

  /// Creates a new user with password.
  ///
  /// Returns the ID of the created user.
  Future<int> createUser({
    required String username,
    required String fullName,
    required String password,
  }) async {
    // Create user
    final userResults = await _db.query(
      '''
      INSERT INTO auth.user (username, full_name)
      VALUES (@username, @fullName)
      RETURNING id
      ''',
      {'username': username, 'fullName': fullName},
    );

    final userId = userResults.first['id'] as int;

    // Create password
    final passwordHash = PasswordHasher.hash(password);
    await _db.execute(
      '''
      INSERT INTO auth.password (id_user, password_hash)
      VALUES (@userId, @passwordHash)
      ''',
      {'userId': userId, 'passwordHash': passwordHash},
    );

    return userId;
  }
}
