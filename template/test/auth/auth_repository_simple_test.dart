import 'package:test/test.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/auth_repository.dart';

/// Integration test for AuthRepository - PostgreSQL Connection Test.
///
/// Prerequisites:
/// 1. PostgreSQL must be running (docker-compose up)
/// 2. Database must be initialized with seed data
/// 3. Test user 'example' with password 'abc123' must exist
///
/// Run this test with:
/// ```
/// dart test test/auth/auth_repository_simple_test.dart
/// ```
void main() {
  late PostgresClient db;
  late AuthRepository repo;

  setUpAll(() async {
    // Initialize database connection
    db = PostgresClient();
    await db.connect();
    repo = AuthRepository(db);

    print('\n✓ Database connection established');
    print('=' * 60);
  });

  tearDownAll(() async {
    // Close database connection
    await db.close();
    print('=' * 60);
    print('✓ Database connection closed\n');
  });

  group('🔌 Database Connection Tests', () {
    test('should connect to PostgreSQL successfully', () async {
      expect(db.isConnected, isTrue);
      print('  ✓ PostgreSQL connection is active');
    });

    test('should query user table and get row count', () async {
      final result = await db.query('SELECT COUNT(*) as count FROM auth.user');

      expect(result, isNotEmpty);
      expect(result.first['count'], isA<int>());
      expect(result.first['count'], greaterThan(0));

      print('  ✓ Database has ${result.first['count']} users in auth.user');
    });

    test('should query password table and get row count', () async {
      final result = await db.query(
        'SELECT COUNT(*) as count FROM auth.password',
      );

      expect(result, isNotEmpty);
      expect(result.first['count'], isA<int>());
      expect(result.first['count'], greaterThan(0));

      print(
        '  ✓ Database has ${result.first['count']} passwords in auth.password',
      );
    });
  });

  group('👤 User Repository Tests', () {
    test('getUserByUsername should find user "example"', () async {
      const username = 'example';

      final user = await repo.getUserByUsername(username);

      expect(user, isNotNull, reason: 'User "example" should exist');
      expect(user!['username'], equals(username));
      expect(user['full_name'], equals('Example User'));
      expect(user['id'], isA<int>());
      expect(user['created_at'], isNotNull);

      print('  ✓ Found user: ${user['username']} - ${user['full_name']}');
      print('    User ID: ${user['id']}');
    });

    test(
      'getUserByUsername should return null for non-existent user',
      () async {
        const username = 'this_user_does_not_exist_xyz';

        final user = await repo.getUserByUsername(username);

        expect(user, isNull);
        print('  ✓ Correctly returned null for non-existent user');
      },
    );

    test('getUserById should find user by ID', () async {
      // First get the example user to know their ID
      final exampleUser = await repo.getUserByUsername('example');
      expect(exampleUser, isNotNull);

      final userId = exampleUser!['id'] as int;

      // Now fetch by ID
      final user = await repo.getUserById(userId);

      expect(user, isNotNull);
      expect(user!['id'], equals(userId));
      expect(user['username'], equals('example'));

      print('  ✓ Found user by ID: ${user['id']} -> ${user['username']}');
    });
  });

  group('🔐 Password Verification Tests', () {
    test('verifyPassword should return TRUE for correct password', () async {
      // Get user ID
      final user = await repo.getUserByUsername('example');
      expect(user, isNotNull);

      final userId = user!['id'] as int;
      const correctPassword = 'abc123';

      // Verify password
      final isValid = await repo.verifyPassword(userId, correctPassword);

      expect(isValid, isTrue);
      print('  ✓ Password "abc123" verified successfully for user "example"');
    });

    test('verifyPassword should return FALSE for incorrect password', () async {
      // Get user ID
      final user = await repo.getUserByUsername('example');
      expect(user, isNotNull);

      final userId = user!['id'] as int;
      const wrongPassword = 'wrong_password_123';

      // Verify password
      final isValid = await repo.verifyPassword(userId, wrongPassword);

      expect(isValid, isFalse);
      print('  ✓ Password verification correctly rejected incorrect password');
    });

    test('verifyPassword should return FALSE for non-existent user', () async {
      const nonExistentUserId = 99999;
      const password = 'any_password';

      final isValid = await repo.verifyPassword(nonExistentUserId, password);

      expect(isValid, isFalse);
      print('  ✓ Password verification correctly handled non-existent user');
    });
  });

  group('✅ Authentication Flow Tests', () {
    test('authenticate should return user for correct credentials', () async {
      const username = 'example';
      const password = 'abc123';

      final user = await repo.authenticate(username, password);

      expect(user, isNotNull);
      expect(user!['username'], equals(username));
      expect(user['full_name'], equals('Example User'));

      print('  ✓ Authentication successful:');
      print('    Username: ${user['username']}');
      print('    Full Name: ${user['full_name']}');
      print('    User ID: ${user['id']}');
    });

    test('authenticate should return NULL for wrong password', () async {
      const username = 'example';
      const wrongPassword = 'wrong_password';

      final user = await repo.authenticate(username, wrongPassword);

      expect(user, isNull);
      print('  ✓ Authentication correctly rejected wrong password');
    });

    test('authenticate should return NULL for non-existent user', () async {
      const username = 'nonexistent_user';
      const password = 'any_password';

      final user = await repo.authenticate(username, password);

      expect(user, isNull);
      print('  ✓ Authentication correctly rejected non-existent user');
    });

    test('authenticate "admin" user with password123', () async {
      const username = 'admin';
      const password = 'password123';

      final user = await repo.authenticate(username, password);

      expect(user, isNotNull);
      expect(user!['username'], equals(username));
      expect(user['full_name'], equals('Administrator User'));

      print('  ✓ Admin authentication successful: ${user['full_name']}');
    });

    test('authenticate "testuser" with password123', () async {
      const username = 'testuser';
      const password = 'password123';

      final user = await repo.authenticate(username, password);

      expect(user, isNotNull);
      expect(user!['username'], equals(username));
      expect(user['full_name'], equals('Test User Demo'));

      print('  ✓ Test user authentication successful: ${user['full_name']}');
    });
  });

  group('📊 Final Summary', () {
    test('display all users in database', () async {
      final users = await db.query('''
        SELECT u.id, u.username, u.full_name, u.created_at
        FROM auth.user u
        ORDER BY u.id
      ''');

      expect(users, isNotEmpty);

      print('\n  📋 All Users in Database:');
      print('  ${'=' * 58}');
      for (final user in users) {
        print(
          '  ID: ${user['id']} | ${user['username'].toString().padRight(15)} | ${user['full_name']}',
        );
      }
      print('  ${'=' * 58}');
      print('  Total: ${users.length} users\n');
    });
  });
}
