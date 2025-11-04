import 'package:test/test.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/auth_repository.dart';

/// Integration test for AuthRepository.
///
/// Prerequisites:
/// 1. PostgreSQL must be running (docker-compose up)
/// 2. Database must be initialized with seed data
/// 3. Test user 'example' with password 'abc123' must exist
///
/// Run this test with:
/// ```
/// dart test test/auth/auth_repository_test.dart
/// ```
void main() {
  late PostgresClient db;
  late AuthRepository repo;

  setUpAll(() async {
    // Initialize database connection
    db = PostgresClient();
    await db.connect();
    repo = AuthRepository(db);

    print('✓ Database connection established');
  });

  tearDownAll(() async {
    // Close database connection
    await db.close();
    print('✓ Database connection closed');
  });

  group('AuthRepository - User Operations', () {
    test('getUserByUsername should return user data for existing user', () async {
      // Arrange
      const username = 'example';

      // Act
      final user = await repo.getUserByUsername(username);

      // Assert
      expect(user, isNotNull, reason: 'User should exist in database');
      expect(user!['username'], equals(username));
      expect(user['full_name'], equals('Example User'));
      expect(user['id'], isA<int>());
      expect(user['created_at'], isNotNull);

      print('✓ Found user: ${user['username']} (${user['full_name']})');
    });

    test('getUserByUsername should return null for non-existent user', () async {
      // Arrange
      const username = 'nonexistent_user_xyz';

      // Act
      final user = await repo.getUserByUsername(username);

      // Assert
      expect(user, isNull, reason: 'Non-existent user should return null');

      print('✓ Correctly returned null for non-existent user');
    });

    test('getUserById should return user data for existing user ID', () async {
      // Arrange - First get a user to know a valid ID
      final exampleUser = await repo.getUserByUsername('example');
      expect(exampleUser, isNotNull);
      
      final userId = exampleUser!['id'] as int;

      // Act
      final user = await repo.getUserById(userId);

      // Assert
      expect(user, isNotNull);
      expect(user!['id'], equals(userId));
      expect(user['username'], equals('example'));

      print('✓ Found user by ID: ${user['id']}');
    });
  });

  group('AuthRepository - Password Verification', () {
    test('verifyPassword should return true for correct password', () async {
      // Arrange
      final user = await repo.getUserByUsername('example');
      expect(user, isNotNull);
      
      final userId = user!['id'] as int;
      const correctPassword = 'abc123';

      // Act
      final isValid = await repo.verifyPassword(userId, correctPassword);

      // Assert
      expect(isValid, isTrue, reason: 'Correct password should be valid');

      print('✓ Password verification successful for user: example');
    });

    test('verifyPassword should return false for incorrect password', () async {
      // Arrange
      final user = await repo.getUserByUsername('example');
      expect(user, isNotNull);
      
      final userId = user!['id'] as int;
      const wrongPassword = 'wrongpassword123';

      // Act
      final isValid = await repo.verifyPassword(userId, wrongPassword);

      // Assert
      expect(isValid, isFalse, reason: 'Incorrect password should be invalid');

      print('✓ Password verification correctly rejected wrong password');
    });

    test('verifyPassword should return false for non-existent user', () async {
      // Arrange
      const nonExistentUserId = 99999;
      const password = 'anypassword';

      // Act
      final isValid = await repo.verifyPassword(nonExistentUserId, password);

      // Assert
      expect(isValid, isFalse, reason: 'Non-existent user should return false');

      print('✓ Correctly returned false for non-existent user ID');
    });
  });

  group('AuthRepository - Authentication', () {
    test('authenticate should return user data for correct credentials', () async {
      // Arrange
      const username = 'example';
      const password = 'abc123';

      // Act
      final user = await repo.authenticate(username, password);

      // Assert
      expect(user, isNotNull, reason: 'Authentication should succeed');
      expect(user!['username'], equals(username));
      expect(user['full_name'], equals('Example User'));

      print('✓ Authentication successful for: $username');
    });

    test('authenticate should return null for incorrect password', () async {
      // Arrange
      const username = 'example';
      const wrongPassword = 'wrongpassword';

      // Act
      final user = await repo.authenticate(username, wrongPassword);

      // Assert
      expect(user, isNull, reason: 'Authentication should fail');

      print('✓ Authentication correctly rejected wrong password');
    });

    test('authenticate should return null for non-existent user', () async {
      // Arrange
      const username = 'nonexistent';
      const password = 'anypassword';

      // Act
      final user = await repo.authenticate(username, password);

      // Assert
      expect(user, isNull, reason: 'Authentication should fail');

      print('✓ Authentication correctly rejected non-existent user');
    });
  });

  group('AuthRepository - Database Connection', () {
    test('should successfully query user table', () async {
      // Act
      final users = await db.query('SELECT COUNT(*) as count FROM auth.user');

      // Assert
      expect(users, isNotEmpty);
      expect(users.first['count'], isA<int>());
      expect(users.first['count'], greaterThan(0));

      print('✓ Database has ${users.first['count']} users');
    });

    test('should successfully query password table', () async {
      // Act
      final passwords = await db.query('SELECT COUNT(*) as count FROM auth.password');

      // Assert
      expect(passwords, isNotEmpty);
      expect(passwords.first['count'], isA<int>());
      expect(passwords.first['count'], greaterThan(0));

      print('✓ Database has ${passwords.first['count']} passwords');
    });
  });
}
