import 'package:test/test.dart';
import 'package:modular_api/modular_api.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/usecases/login.dart';
import 'package:example/modules/auth/usecases/refresh.dart';

/// Integration test for Refresh UseCase.
///
/// Prerequisites:
/// 1. PostgreSQL must be running (docker-compose up)
/// 2. Database must be initialized with seed data
/// 3. Test user 'example' with password 'abc123' must exist
///
/// Run this test with:
/// ```
/// dart test test/auth/refresh_test.dart
/// ```
void main() {
  /// Helper function to perform login and get refresh token
  Future<String> performLogin() async {
    final loginUseCase = LoginUseCase(
      input: LoginInput(username: 'example', password: 'abc123'),
    );
    await loginUseCase.execute();
    return loginUseCase.output.refreshToken;
  }

  group('RefreshUseCase - Basic Functionality', () {
    test('should successfully refresh with valid token', () async {
      // Arrange - First login to get a refresh token
      final refreshToken = await performLogin();

      final useCase = RefreshUseCase(
        input: RefreshInput(refreshToken: refreshToken),
      );

      // Act
      await useCase.execute();
      final output = useCase.output;

      // Assert
      expect(
        output.accessToken,
        isNotEmpty,
        reason: 'New access token should be generated',
      );
      expect(output.tokenType, equals('Bearer'));
      expect(output.expiresIn, greaterThan(0));

      print('✓ Token refresh successful');
      print('  New Access Token: ${output.accessToken.substring(0, 20)}...');
      print('  Expires In: ${output.expiresIn} seconds');
    });

    test('should generate valid new access token', () async {
      // Arrange
      final refreshToken = await performLogin();
      final useCase = RefreshUseCase(
        input: RefreshInput(refreshToken: refreshToken),
      );

      // Act
      await useCase.execute();
      final newAccessToken = useCase.output.accessToken;

      // Assert - Verify JWT can be decoded
      final payload = JwtHelper.verifyToken(newAccessToken);
      expect(payload['sub'], isNotNull, reason: 'User ID should be present');
      expect(payload['username'], equals('example'));
      expect(payload['type'], equals('access'));

      print('✓ New access token is valid JWT');
      print('  User ID: ${payload['sub']}');
      print('  Username: ${payload['username']}');
    });

    test('should fail with invalid refresh token', () async {
      // Arrange
      final useCase = RefreshUseCase(
        input: RefreshInput(refreshToken: 'invalid.jwt.token'),
      );

      // Act & Assert
      expect(
        () => useCase.execute(),
        throwsA(isA<ArgumentError>()),
        reason: 'Should throw error for invalid token',
      );

      print('✓ Correctly rejected invalid refresh token');
    });

    test('should fail with empty refresh token', () async {
      // Arrange
      final useCase = RefreshUseCase(input: RefreshInput(refreshToken: ''));

      // Act
      final validationError = useCase.validate();

      // Assert
      expect(validationError, isNotNull);
      expect(validationError, contains('required'));

      print('✓ Validation rejected empty refresh token');
    });
  });

  group('RefreshUseCase - Token Rotation', () {
    test('should return new refresh token when rotation is enabled', () async {
      // Arrange
      final oldRefreshToken = await performLogin();

      final useCase = RefreshUseCase(
        input: RefreshInput(refreshToken: oldRefreshToken),
        enableRotation: true,
      );

      // Act
      await useCase.execute();
      final output = useCase.output;

      // Assert
      expect(
        output.refreshToken,
        isNotNull,
        reason: 'New refresh token should be returned when rotation is enabled',
      );
      expect(
        output.refreshToken,
        isNot(equals(oldRefreshToken)),
        reason: 'New refresh token should be different from old one',
      );

      print('✓ Token rotation successful');
      print('  Old Token: ${oldRefreshToken.substring(0, 20)}...');
      print('  New Token: ${output.refreshToken!.substring(0, 20)}...');
    });

    test('should revoke old refresh token after rotation', () async {
      // Arrange
      final oldRefreshToken = await performLogin();
      final oldPayload = JwtHelper.verifyToken(oldRefreshToken);
      final oldTokenId = int.parse(oldPayload['jti'] as String);

      // Act - Use refresh with rotation enabled
      final useCase = RefreshUseCase(
        input: RefreshInput(refreshToken: oldRefreshToken),
        enableRotation: true,
      );
      await useCase.execute();

      // Assert - Check old token is revoked in database
      final db = PostgresClient();
      await db.connect();

      try {
        final results = await db.query(
          '''
          SELECT id, revoked
          FROM auth.refresh_token
          WHERE id = @tokenId
          ''',
          {'tokenId': oldTokenId},
        );

        expect(results, isNotEmpty);
        final token = results.first;
        expect(
          token['revoked'],
          isTrue,
          reason: 'Old token should be revoked after rotation',
        );

        print('✓ Old token revoked after rotation');
        print('  Token ID: $oldTokenId');
        print('  Revoked: ${token['revoked']}');
      } finally {
        await db.close();
      }
    });

    test('should fail to use revoked token', () async {
      // Arrange - Login and rotate token
      final oldRefreshToken = await performLogin();

      final firstRefresh = RefreshUseCase(
        input: RefreshInput(refreshToken: oldRefreshToken),
        enableRotation: true,
      );
      await firstRefresh.execute();

      // Act - Try to use the old (now revoked) token again
      final secondRefresh = RefreshUseCase(
        input: RefreshInput(refreshToken: oldRefreshToken),
      );

      // Assert
      expect(
        () => secondRefresh.execute(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('revoked'),
          ),
        ),
        reason: 'Should fail to use revoked token',
      );

      print('✓ Correctly rejected revoked token');
    });

    test('should link new token to previous token', () async {
      // Arrange
      final oldRefreshToken = await performLogin();
      final oldPayload = JwtHelper.verifyToken(oldRefreshToken);
      final oldTokenId = int.parse(oldPayload['jti'] as String);

      // Act
      final useCase = RefreshUseCase(
        input: RefreshInput(refreshToken: oldRefreshToken),
        enableRotation: true,
      );
      await useCase.execute();

      final newRefreshToken = useCase.output.refreshToken!;
      final newPayload = JwtHelper.verifyToken(newRefreshToken);
      final newTokenId = int.parse(newPayload['jti'] as String);

      // Assert - Check database linkage
      final db = PostgresClient();
      await db.connect();

      try {
        final results = await db.query(
          '''
          SELECT id, previous_id
          FROM auth.refresh_token
          WHERE id = @tokenId
          ''',
          {'tokenId': newTokenId},
        );

        expect(results, isNotEmpty);
        final token = results.first;
        expect(
          token['previous_id'],
          equals(oldTokenId),
          reason: 'New token should reference previous token ID',
        );

        print('✓ Token chain maintained');
        print('  Old Token ID: $oldTokenId');
        print('  New Token ID: $newTokenId');
        print('  Previous ID: ${token['previous_id']}');
      } finally {
        await db.close();
      }
    });

    test(
      'should not return new refresh token when rotation is disabled',
      () async {
        // Arrange
        final refreshToken = await performLogin();

        final useCase = RefreshUseCase(
          input: RefreshInput(refreshToken: refreshToken),
          enableRotation: false,
        );

        // Act
        await useCase.execute();
        final output = useCase.output;

        // Assert
        expect(
          output.refreshToken,
          isNull,
          reason:
              'No new refresh token should be returned when rotation is disabled',
        );

        print('✓ No token rotation when disabled');
      },
    );
  });

  group('RefreshUseCase - Security Validations', () {
    test('should fail with expired refresh token', () async {
      // This test would require manipulating database timestamps
      // or waiting for actual expiration, so it's a conceptual test
      // In production, you'd mock the database or use a test-specific short expiration

      print('⚠️  Expiration test requires time manipulation (skipped)');
      // TODO: Implement with database time manipulation or mocking
    });

    test('should verify token belongs to correct user', () async {
      // Arrange
      final refreshToken = await performLogin();
      final payload = JwtHelper.verifyToken(refreshToken);
      final userId = int.parse(payload['sub'] as String);

      // Act
      final useCase = RefreshUseCase(
        input: RefreshInput(refreshToken: refreshToken),
      );
      await useCase.execute();

      // Assert - Verify user ID consistency
      final newAccessToken = useCase.output.accessToken;
      final newPayload = JwtHelper.verifyToken(newAccessToken);
      final newUserId = int.parse(newPayload['sub'] as String);

      expect(
        newUserId,
        equals(userId),
        reason: 'User ID should be consistent across tokens',
      );

      print('✓ User ID consistency verified');
      print('  Original User ID: $userId');
      print('  New Token User ID: $newUserId');
    });

    test('should prevent use of token for non-existent user', () async {
      // This would require creating a token for a user, then deleting the user
      // It's more of an edge case but important for security
      print(
        '⚠️  Non-existent user test requires user deletion setup (skipped)',
      );
      // TODO: Implement with user deletion scenario
    });
  });

  group('RefreshUseCase - Database Consistency', () {
    test('should maintain token records in database', () async {
      // Arrange
      final refreshToken = await performLogin();

      // Count tokens before refresh
      final db = PostgresClient();
      await db.connect();

      try {
        final countBefore = await db.query(
          'SELECT COUNT(*) as count FROM auth.refresh_token',
        );
        final beforeCount = countBefore.first['count'] as int;

        // Act - Refresh with rotation
        final useCase = RefreshUseCase(
          input: RefreshInput(refreshToken: refreshToken),
          enableRotation: true,
        );
        await useCase.execute();

        // Assert - Count should increase by 1 (new token added, old one kept but revoked)
        final countAfter = await db.query(
          'SELECT COUNT(*) as count FROM auth.refresh_token',
        );
        final afterCount = countAfter.first['count'] as int;

        expect(
          afterCount,
          equals(beforeCount + 1),
          reason: 'Should have one additional token record',
        );

        print('✓ Token records maintained');
        print('  Tokens before: $beforeCount');
        print('  Tokens after: $afterCount');
      } finally {
        await db.close();
      }
    });

    test('should verify new token is not revoked', () async {
      // Arrange
      final refreshToken = await performLogin();

      final useCase = RefreshUseCase(
        input: RefreshInput(refreshToken: refreshToken),
        enableRotation: true,
      );

      // Act
      await useCase.execute();
      final newRefreshToken = useCase.output.refreshToken!;
      final payload = JwtHelper.verifyToken(newRefreshToken);
      final tokenId = int.parse(payload['jti'] as String);

      // Assert - Check database
      final db = PostgresClient();
      await db.connect();

      try {
        final results = await db.query(
          '''
          SELECT revoked, expires_at
          FROM auth.refresh_token
          WHERE id = @tokenId
          ''',
          {'tokenId': tokenId},
        );

        expect(results, isNotEmpty);
        final token = results.first;
        expect(
          token['revoked'],
          isFalse,
          reason: 'New token should not be revoked',
        );

        // PostgreSQL returns timestamps as DateTime objects, not strings
        final expiresAt = token['expires_at'] as DateTime;
        expect(
          expiresAt.isAfter(DateTime.now()),
          isTrue,
          reason: 'New token should not be expired',
        );

        print('✓ New token is active and valid');
        print('  Token ID: $tokenId');
        print('  Revoked: ${token['revoked']}');
        print('  Expires at: $expiresAt');
      } finally {
        await db.close();
      }
    });

    test('should handle multiple sequential refreshes', () async {
      // Arrange
      var currentToken = await performLogin();

      // Act - Perform 3 sequential refreshes
      for (var i = 0; i < 3; i++) {
        final useCase = RefreshUseCase(
          input: RefreshInput(refreshToken: currentToken),
          enableRotation: true,
        );
        await useCase.execute();

        expect(useCase.output.refreshToken, isNotNull);
        currentToken = useCase.output.refreshToken!;

        print('  Refresh ${i + 1} completed');
      }

      // Assert - Final token should still work
      final finalUseCase = RefreshUseCase(
        input: RefreshInput(refreshToken: currentToken),
      );
      await finalUseCase.execute();

      expect(finalUseCase.output.accessToken, isNotEmpty);

      print('✓ Multiple sequential refreshes successful');
    });
  });
}
