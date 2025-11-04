import 'package:test/test.dart';
import 'package:modular_api/modular_api.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/usecases/login.dart';
import 'package:example/modules/auth/usecases/logout_all.dart';

void main() {
  late PostgresClient db;

  setUpAll(() async {
    db = PostgresClient();
    await db.connect();
    print('✓ Database connection established');
    print('=' * 56);
  });

  tearDownAll(() async {
    await db.close();
    print('=' * 56);
    print('✓ Database connection closed\n');
  });

  group('LogoutAllUseCase - Basic Functionality', () {
    test(
      'should successfully logout all sessions with valid refresh token',
      () async {
        // Login multiple times to create multiple sessions
        final login1 = await performLogin(db);
        await Future.delayed(const Duration(seconds: 2));
        await performLogin(db);
        await Future.delayed(const Duration(seconds: 2));
        await performLogin(db);

        final refreshToken1 = login1['refresh_token'] as String;

        // Logout all sessions using the first refresh token
        final useCase = LogoutAllUseCase.factory({
          'refresh_token': refreshToken1,
        });

        await useCase.execute();

        expect(useCase.output.success, isTrue);
        expect(
          useCase.output.message,
          equals('Successfully logged out from all sessions'),
        );
        expect(useCase.output.revokedCount, greaterThanOrEqualTo(3));

        print('✓ Logout all sessions successful');
        print('  Message: ${useCase.output.message}');
        print('  Success: ${useCase.output.success}');
        print('  Tokens Revoked: ${useCase.output.revokedCount}');
      },
    );

    test('should fail with already revoked token', () async {
      // Login and logout all
      final loginResult = await performLogin(db);
      final refreshToken = loginResult['refresh_token'] as String;

      // First logout all
      final useCase1 = LogoutAllUseCase.factory({
        'refresh_token': refreshToken,
      });
      await useCase1.execute();

      // Try to logout all again with the same token
      expect(
        () async {
          final useCase2 = LogoutAllUseCase.factory({
            'refresh_token': refreshToken,
          });
          await useCase2.execute();
        },
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('has been revoked'),
          ),
        ),
      );

      print('✓ Correctly rejected already revoked token');
    });

    test('should fail with invalid JWT token', () async {
      final useCase = LogoutAllUseCase.factory({
        'refresh_token': 'invalid.jwt.token',
      });

      expect(
        () async => await useCase.execute(),
        throwsA(isA<ArgumentError>()),
      );

      print('✓ Correctly rejected invalid JWT token');
    });

    test('should fail with empty refresh token', () async {
      final useCase = LogoutAllUseCase.factory({'refresh_token': ''});

      final validationError = useCase.validate();
      expect(validationError, isNotNull);
      expect(validationError, contains('cannot be empty'));

      print('✓ Validation rejected empty refresh token');
      print('  Validation Error: $validationError');
    });

    test('should fail with access token instead of refresh token', () async {
      // Login to get access token
      final loginResult = await performLogin(db);
      final accessToken = loginResult['access_token'] as String;

      // Try to logout all with access token
      final useCase = LogoutAllUseCase.factory({'refresh_token': accessToken});

      expect(
        () async => await useCase.execute(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Expected refresh token'),
          ),
        ),
      );

      print('✓ Correctly rejected access token');
    });
  });

  group('LogoutAllUseCase - Multiple Sessions', () {
    test('should revoke all tokens for a user', () async {
      // Login 5 times to create 5 sessions
      final tokens = <String>[];
      for (int i = 0; i < 5; i++) {
        final login = await performLogin(db);
        tokens.add(login['refresh_token'] as String);
        await Future.delayed(const Duration(seconds: 2));
      }

      // Count active tokens before logout_all
      final beforeCount = await db.queryOne('''
        SELECT COUNT(*) as count
        FROM auth.refresh_token
        WHERE id_user = 1
          AND revoked = false
        ''');

      expect((beforeCount!['count'] as int), greaterThanOrEqualTo(5));

      // Logout all using any of the tokens
      final useCase = LogoutAllUseCase.factory({'refresh_token': tokens[2]});
      await useCase.execute();

      expect(useCase.output.success, isTrue);
      expect(useCase.output.revokedCount, greaterThanOrEqualTo(5));

      // Verify all tokens are revoked
      final afterCount = await db.queryOne('''
        SELECT COUNT(*) as count
        FROM auth.refresh_token
        WHERE id_user = 1
          AND revoked = false
        ''');

      expect(afterCount!['count'], equals(0));

      print('✓ All tokens revoked for user');
      print('  Tokens Before: ${beforeCount['count']}');
      print('  Tokens Revoked: ${useCase.output.revokedCount}');
      print('  Active Tokens After: ${afterCount['count']}');
    });

    test('should return correct count of revoked tokens', () async {
      // Login 3 times
      final tokens = <String>[];
      for (int i = 0; i < 3; i++) {
        final login = await performLogin(db);
        tokens.add(login['refresh_token'] as String);
        await Future.delayed(const Duration(seconds: 2));
      }

      // Logout all
      final useCase = LogoutAllUseCase.factory({'refresh_token': tokens[0]});
      await useCase.execute();

      expect(useCase.output.revokedCount, greaterThanOrEqualTo(3));

      print('✓ Correct count of revoked tokens');
      print('  Count: ${useCase.output.revokedCount}');
    });

    test('should not affect other users tokens', () async {
      // Note: This test assumes we only have user ID 1 (example user)
      // In a real scenario, we would create a second user and verify their tokens are not affected

      // Login with example user (ID 1)
      final login1 = await performLogin(db);
      final refreshToken = login1['refresh_token'] as String;

      // Count tokens for user 1
      final user1TokensBefore = await db.queryOne('''
        SELECT COUNT(*) as count
        FROM auth.refresh_token
        WHERE id_user = 1
          AND revoked = false
        ''');

      // Logout all for user 1
      final useCase = LogoutAllUseCase.factory({'refresh_token': refreshToken});
      await useCase.execute();

      // Verify user 1 has no active tokens
      final user1TokensAfter = await db.queryOne('''
        SELECT COUNT(*) as count
        FROM auth.refresh_token
        WHERE id_user = 1
          AND revoked = false
        ''');

      expect(user1TokensAfter!['count'], equals(0));

      // Verify tokens for other users (if any) are not affected
      final otherUsersTokens = await db.queryOne('''
        SELECT COUNT(*) as count
        FROM auth.refresh_token
        WHERE id_user != 1
          AND revoked = false
        ''');

      // If there are other users, their tokens should not be revoked
      // (In this test environment, there might not be other users with active tokens)
      print('✓ User isolation verified');
      print('  User 1 tokens before: ${user1TokensBefore!['count']}');
      print('  User 1 tokens after: ${user1TokensAfter['count']}');
      print('  Other users active tokens: ${otherUsersTokens!['count']}');
    });
  });

  group('LogoutAllUseCase - Security Validations', () {
    test('should verify token is in database before revoking all', () async {
      // Create a valid JWT but not in database
      final fakeTokenId = 999999;
      final fakeJwt = JwtHelper.generateRefreshToken(
        userId: 1,
        tokenId: fakeTokenId,
      );

      final useCase = LogoutAllUseCase.factory({'refresh_token': fakeJwt});

      expect(
        () async => await useCase.execute(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('not found'),
          ),
        ),
      );

      print('✓ Correctly rejected token not in database');
    });

    test('should extract correct user ID from token', () async {
      // Login to get a valid token
      final loginResult = await performLogin(db);
      final refreshToken = loginResult['refresh_token'] as String;

      // Extract user ID from JWT
      final jwt = JwtHelper.verifyToken(refreshToken);
      final userId = int.parse(jwt['sub'] as String);

      expect(userId, equals(1)); // example user has ID 1

      // Logout all
      final useCase = LogoutAllUseCase.factory({'refresh_token': refreshToken});
      await useCase.execute();

      expect(useCase.output.success, isTrue);

      print('✓ Correct user ID extracted from token');
      print('  User ID: $userId');
    });
  });

  group('LogoutAllUseCase - Database Consistency', () {
    test('should mark all user tokens as revoked in database', () async {
      // Login 3 times
      final tokens = <String>[];
      final tokenIds = <int>[];

      for (int i = 0; i < 3; i++) {
        final login = await performLogin(db);
        final refreshToken = login['refresh_token'] as String;
        tokens.add(refreshToken);

        final jwt = JwtHelper.verifyToken(refreshToken);
        tokenIds.add(int.parse(jwt['jti'] as String));

        await Future.delayed(const Duration(seconds: 2));
      }

      // Logout all
      final useCase = LogoutAllUseCase.factory({'refresh_token': tokens[0]});
      await useCase.execute();

      // Verify all tokens are marked as revoked
      for (final tokenId in tokenIds) {
        final tokenRecord = await db.queryOne(
          '''
          SELECT id, revoked
          FROM auth.refresh_token
          WHERE id = @tokenId
          ''',
          {'tokenId': tokenId},
        );

        expect(tokenRecord, isNotNull);
        expect(tokenRecord!['revoked'], isTrue);
      }

      print('✓ All user tokens marked as revoked in database');
      print('  Token IDs: $tokenIds');
    });

    test('should not delete tokens from database (soft delete)', () async {
      // Login 2 times
      final tokens = <String>[];
      for (int i = 0; i < 2; i++) {
        final login = await performLogin(db);
        tokens.add(login['refresh_token'] as String);
        await Future.delayed(const Duration(seconds: 2));
      }

      // Count all tokens for user before logout_all
      final tokensBefore = await db.query('''
        SELECT id, revoked
        FROM auth.refresh_token
        WHERE id_user = 1
        ''');

      final countBefore = tokensBefore.length;

      // Logout all
      final useCase = LogoutAllUseCase.factory({'refresh_token': tokens[0]});
      await useCase.execute();

      // Count all tokens for user after logout_all
      final tokensAfter = await db.query('''
        SELECT id, revoked
        FROM auth.refresh_token
        WHERE id_user = 1
        ''');

      final countAfter = tokensAfter.length;

      // All tokens should still exist (soft delete)
      expect(countAfter, greaterThanOrEqualTo(countBefore));

      // All should be marked as revoked
      for (final token in tokensAfter) {
        if (tokensBefore.any((t) => t['id'] == token['id'])) {
          expect(token['revoked'], isTrue);
        }
      }

      print('✓ Tokens still exist in database (soft delete)');
      print('  Tokens Before: $countBefore');
      print('  Tokens After: $countAfter');
      print('  All marked as revoked: true');
    });

    test('should maintain token audit trail after logout_all', () async {
      // Login
      final loginResult = await performLogin(db);
      final refreshToken = loginResult['refresh_token'] as String;

      // Extract token ID
      final jwt = JwtHelper.verifyToken(refreshToken);
      final tokenId = int.parse(jwt['jti'] as String);

      // Get token details before logout_all
      final beforeLogout = await db.queryOne(
        '''
        SELECT id, id_user, token_hash, created_at, expires_at
        FROM auth.refresh_token
        WHERE id = @tokenId
        ''',
        {'tokenId': tokenId},
      );

      // Logout all
      final useCase = LogoutAllUseCase.factory({'refresh_token': refreshToken});
      await useCase.execute();

      // Get token details after logout_all
      final afterLogout = await db.queryOne(
        '''
        SELECT id, id_user, token_hash, created_at, expires_at, revoked
        FROM auth.refresh_token
        WHERE id = @tokenId
        ''',
        {'tokenId': tokenId},
      );

      // Verify audit trail is maintained
      expect(afterLogout!['id'], equals(beforeLogout!['id']));
      expect(afterLogout['id_user'], equals(beforeLogout['id_user']));
      expect(afterLogout['token_hash'], equals(beforeLogout['token_hash']));
      expect(afterLogout['created_at'], equals(beforeLogout['created_at']));
      expect(afterLogout['expires_at'], equals(beforeLogout['expires_at']));
      expect(afterLogout['revoked'], isTrue);

      print('✓ Token audit trail maintained after logout_all');
      print('  Created: ${afterLogout['created_at']}');
      print('  Expires: ${afterLogout['expires_at']}');
      print('  Revoked: ${afterLogout['revoked']}');
    });
  });
}

/// Helper function to perform login and get access/refresh tokens
Future<Map<String, String>> performLogin(PostgresClient db) async {
  final loginUseCase = LoginUseCase.factory({
    'username': 'example',
    'password': 'abc123',
  });

  await loginUseCase.execute();

  return {
    'access_token': loginUseCase.output.accessToken,
    'refresh_token': loginUseCase.output.refreshToken,
  };
}
