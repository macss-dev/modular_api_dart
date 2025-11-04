import 'package:test/test.dart';
import 'package:modular_api/modular_api.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/usecases/login.dart';

/// Integration test for Login UseCase.
///
/// Prerequisites:
/// 1. PostgreSQL must be running (docker-compose up)
/// 2. Database must be initialized with seed data
/// 3. Test user 'example' with password 'abc123' must exist
///
/// Run this test with:
/// ```
/// dart test test/auth/login_test.dart
/// ```
void main() {
  group('LoginUseCase - Integration Tests', () {
    test('should successfully login with correct credentials', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(username: 'example', password: 'abc123'),
      );

      // Act
      await useCase.execute();
      final output = useCase.output;

      // Assert
      expect(
        output.accessToken,
        isNotEmpty,
        reason: 'Access token should be generated',
      );
      expect(output.tokenType, equals('Bearer'));
      expect(
        output.expiresIn,
        greaterThan(0),
        reason: 'Expires in should be positive',
      );
      expect(
        output.refreshToken,
        isNotEmpty,
        reason: 'Refresh token should be generated',
      );

      print('✓ Login successful');
      print('  Access Token: ${output.accessToken.substring(0, 20)}...');
      print('  Token Type: ${output.tokenType}');
      print('  Expires In: ${output.expiresIn} seconds');
      print('  Refresh Token: ${output.refreshToken.substring(0, 20)}...');
    });

    test('should generate valid JWT access token', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(username: 'example', password: 'abc123'),
      );

      // Act
      await useCase.execute();
      final accessToken = useCase.output.accessToken;

      // Assert - Verify JWT can be decoded
      final payload = JwtHelper.verifyToken(accessToken);
      expect(
        payload['sub'],
        isNotNull,
        reason: 'Subject (user ID) should be present',
      );
      expect(payload['username'], equals('example'));
      expect(payload['type'], equals('access'));
      expect(payload['iat'], isNotNull, reason: 'Issued at should be present');
      expect(payload['exp'], isNotNull, reason: 'Expiration should be present');

      print('✓ Access token is valid JWT');
      print('  User ID: ${payload['sub']}');
      print('  Username: ${payload['username']}');
      print('  Type: ${payload['type']}');
    });

    test('should generate valid JWT refresh token', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(username: 'example', password: 'abc123'),
      );

      // Act
      await useCase.execute();
      final refreshToken = useCase.output.refreshToken;

      // Assert - Verify JWT can be decoded
      final payload = JwtHelper.verifyToken(refreshToken);
      expect(
        payload['sub'],
        isNotNull,
        reason: 'Subject (user ID) should be present',
      );
      expect(
        payload['jti'],
        isNotNull,
        reason: 'JWT ID (token ID) should be present',
      );
      expect(payload['type'], equals('refresh'));
      expect(payload['iat'], isNotNull, reason: 'Issued at should be present');
      expect(payload['exp'], isNotNull, reason: 'Expiration should be present');

      print('✓ Refresh token is valid JWT');
      print('  User ID: ${payload['sub']}');
      print('  Token ID: ${payload['jti']}');
      print('  Type: ${payload['type']}');
    });

    test('should store refresh token hash in database', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(username: 'example', password: 'abc123'),
      );

      // Act
      await useCase.execute();
      final refreshToken = useCase.output.refreshToken;

      // Extract token ID from JWT
      final payload = JwtHelper.verifyToken(refreshToken);
      final tokenId = int.parse(payload['jti'] as String);

      // Verify token exists in database
      final db = PostgresClient();
      await db.connect();

      try {
        final results = await db.query(
          '''
          SELECT id, id_user, revoked, expires_at
          FROM auth.refresh_token
          WHERE id = @tokenId
          ''',
          {'tokenId': tokenId},
        );

        // Assert
        expect(results, isNotEmpty, reason: 'Token should exist in database');
        final token = results.first;
        expect(
          token['revoked'],
          isFalse,
          reason: 'Token should not be revoked',
        );
        expect(token['id_user'], isA<int>(), reason: 'Should have a user ID');

        print('✓ Refresh token stored in database');
        print('  Token ID: $tokenId');
        print('  User ID: ${token['id_user']}');
        print('  Revoked: ${token['revoked']}');
      } finally {
        await db.close();
      }
    });

    test('should fail with incorrect username', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(username: 'nonexistent', password: 'abc123'),
      );

      // Act & Assert
      expect(
        () => useCase.execute(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid credentials'),
          ),
        ),
        reason: 'Should throw error for invalid username',
      );

      print('✓ Correctly rejected invalid username');
    });

    test('should fail with incorrect password', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(username: 'example', password: 'wrongpassword'),
      );

      // Act & Assert
      expect(
        () => useCase.execute(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid credentials'),
          ),
        ),
        reason: 'Should throw error for invalid password',
      );

      print('✓ Correctly rejected invalid password');
    });

    test('should validate empty username', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(username: '', password: 'abc123'),
      );

      // Act
      final validationError = useCase.validate();

      // Assert
      expect(validationError, isNotNull);
      expect(validationError, contains('required'));

      print('✓ Validation rejected empty username');
    });

    test('should validate username length', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(
          username: 'ab', // Too short
          password: 'abc123',
        ),
      );

      // Act
      final validationError = useCase.validate();

      // Assert
      expect(validationError, isNotNull);
      expect(validationError, contains('between 3 and 16 characters'));

      print('✓ Validation rejected username that is too short');
    });

    test('should validate password length', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(
          username: 'example',
          password: '12345', // Too short
        ),
      );

      // Act
      final validationError = useCase.validate();

      // Assert
      expect(validationError, isNotNull);
      expect(validationError, contains('at least 6 characters'));

      print('✓ Validation rejected password that is too short');
    });

    test('should generate different tokens on multiple logins', () async {
      // Arrange & Act
      final useCase1 = LoginUseCase(
        input: LoginInput(username: 'example', password: 'abc123'),
      );
      await useCase1.execute();

      // Wait enough time to ensure different timestamps in JWT (issued at)
      await Future.delayed(Duration(seconds: 2));

      final useCase2 = LoginUseCase(
        input: LoginInput(username: 'example', password: 'abc123'),
      );
      await useCase2.execute();

      // Assert - Tokens should be different
      expect(
        useCase1.output.accessToken,
        isNot(equals(useCase2.output.accessToken)),
        reason: 'Access tokens should be unique',
      );
      expect(
        useCase1.output.refreshToken,
        isNot(equals(useCase2.output.refreshToken)),
        reason: 'Refresh tokens should be unique',
      );

      print('✓ Multiple logins generate unique tokens');
    });
  });

  group('LoginUseCase - Database Consistency', () {
    test('should verify user exists before authentication', () async {
      // Arrange
      final db = PostgresClient();
      await db.connect();

      try {
        final users = await db.query(
          '''
          SELECT id, username
          FROM auth.user
          WHERE username = @username
          ''',
          {'username': 'example'},
        );

        // Assert
        expect(users, isNotEmpty, reason: 'Test user should exist in database');
        print('✓ Test user exists in database: ${users.first['username']}');
      } finally {
        await db.close();
      }
    });

    test('should verify password record exists for user', () async {
      // Arrange
      final db = PostgresClient();
      await db.connect();

      try {
        final passwords = await db.query(
          '''
          SELECT p.id, p.id_user
          FROM auth.password p
          JOIN auth.user u ON p.id_user = u.id
          WHERE u.username = @username
          ''',
          {'username': 'example'},
        );

        // Assert
        expect(
          passwords,
          isNotEmpty,
          reason: 'Password record should exist for test user',
        );
        print('✓ Password record exists for user');
      } finally {
        await db.close();
      }
    });

    test('should create refresh_token record after login', () async {
      // Arrange
      final useCase = LoginUseCase(
        input: LoginInput(username: 'example', password: 'abc123'),
      );

      // Act
      await useCase.execute();
      final refreshToken = useCase.output.refreshToken;
      final payload = JwtHelper.verifyToken(refreshToken);
      final tokenId = int.parse(payload['jti'] as String);

      // Assert - Check database
      final db = PostgresClient();
      await db.connect();

      try {
        final tokens = await db.query(
          '''
          SELECT id, id_user, revoked, created_at, expires_at
          FROM auth.refresh_token
          WHERE id = @tokenId
          ''',
          {'tokenId': tokenId},
        );

        expect(
          tokens,
          isNotEmpty,
          reason: 'Refresh token should be in database',
        );
        final token = tokens.first;
        expect(token['revoked'], isFalse);

        // PostgreSQL returns timestamps as DateTime objects, not strings
        final createdAt = token['created_at'] as DateTime;
        final expiresAt = token['expires_at'] as DateTime;
        expect(
          expiresAt.isAfter(createdAt),
          isTrue,
          reason: 'Expiration should be after creation',
        );

        print('✓ Refresh token record created successfully');
        print('  Created at: $createdAt');
        print('  Expires at: $expiresAt');
      } finally {
        await db.close();
      }
    });
  });
}
