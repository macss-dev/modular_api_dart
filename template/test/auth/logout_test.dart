import 'package:test/test.dart';
import 'package:modular_api/modular_api.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/usecases/login.dart';
import 'package:example/modules/auth/usecases/logout.dart';

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

  group('LogoutUseCase - Basic Functionality', () {
    test('should successfully logout with valid refresh token', () async {
      // First, login to get a valid refresh token
      final loginResult = await performLogin(db);
      final refreshToken = loginResult['refresh_token'] as String;

      // Now logout
      final useCase = LogoutUseCase.factory({'refresh_token': refreshToken});

      await useCase.execute();

      expect(useCase.output.success, isTrue);
      expect(useCase.output.message, equals('Successfully logged out'));

      print('✓ Logout successful');
      print('  Message: ${useCase.output.message}');
      print('  Success: ${useCase.output.success}');
    });

    test('should fail with already revoked token', () async {
      // Login and logout
      final loginResult = await performLogin(db);
      final refreshToken = loginResult['refresh_token'] as String;

      // First logout
      final useCase1 = LogoutUseCase.factory({'refresh_token': refreshToken});
      await useCase1.execute();

      // Try to logout again with the same token
      final useCase2 = LogoutUseCase.factory({'refresh_token': refreshToken});
      await useCase2.execute();

      expect(useCase2.output.success, isFalse);
      expect(useCase2.output.message, contains('already revoked'));

      print('✓ Correctly rejected already revoked token');
      print('  Message: ${useCase2.output.message}');
    });

    test('should fail with invalid JWT token', () async {
      final useCase = LogoutUseCase.factory({
        'refresh_token': 'invalid.jwt.token',
      });

      expect(
        () async => await useCase.execute(),
        throwsA(isA<ArgumentError>()),
      );

      print('✓ Correctly rejected invalid JWT token');
    });

    test('should fail with empty refresh token', () async {
      final useCase = LogoutUseCase.factory({'refresh_token': ''});

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

      // Try to logout with access token
      final useCase = LogoutUseCase.factory({'refresh_token': accessToken});

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

  group('LogoutUseCase - Security Validations', () {
    test('should verify token is in database before revoking', () async {
      // Create a valid JWT but not in database
      final fakeTokenId = 999999;
      final fakeJwt = JwtHelper.generateRefreshToken(
        userId: 1,
        tokenId: fakeTokenId,
      );

      final useCase = LogoutUseCase.factory({'refresh_token': fakeJwt});

      await useCase.execute();

      expect(useCase.output.success, isFalse);
      expect(useCase.output.message, contains('not found'));

      print('✓ Correctly rejected token not in database');
    });

    test('should verify token ID matches in JWT and database', () async {
      // Login twice to get two different tokens
      final login1 = await performLogin(db);
      await Future.delayed(const Duration(seconds: 2));
      final login2 = await performLogin(db);

      final token1 = login1['refresh_token'] as String;
      final token2 = login2['refresh_token'] as String;

      // Verify they are different tokens
      expect(token1, isNot(equals(token2)));

      // Logout with token1 should work
      final useCase1 = LogoutUseCase.factory({'refresh_token': token1});
      await useCase1.execute();
      expect(useCase1.output.success, isTrue);

      // Logout with token2 should also work
      final useCase2 = LogoutUseCase.factory({'refresh_token': token2});
      await useCase2.execute();
      expect(useCase2.output.success, isTrue);

      print('✓ Token ID verification working correctly');
      print('  Token 1 revoked successfully');
      print('  Token 2 revoked successfully');
    });
  });

  group('LogoutUseCase - Database Consistency', () {
    test('should mark token as revoked in database', () async {
      // Login
      final loginResult = await performLogin(db);
      final refreshToken = loginResult['refresh_token'] as String;

      // Extract token ID from JWT
      final jwt = JwtHelper.verifyToken(refreshToken);
      final tokenId = int.parse(jwt['jti'] as String);

      // Logout
      final useCase = LogoutUseCase.factory({'refresh_token': refreshToken});
      await useCase.execute();

      // Verify token is marked as revoked in database
      final tokenRecord = await db.queryOne(
        '''
        SELECT id, revoked
        FROM auth.refresh_token
        WHERE id = @tokenId
        ''',
        {'tokenId': tokenId},
      );

      expect(tokenRecord, isNotNull);
      expect(tokenRecord!['id'], equals(tokenId));
      expect(tokenRecord['revoked'], isTrue);

      print('✓ Token marked as revoked in database');
      print('  Token ID: ${tokenRecord['id']}');
      print('  Revoked: ${tokenRecord['revoked']}');
    });

    test('should not delete token from database (soft delete)', () async {
      // Login
      final loginResult = await performLogin(db);
      final refreshToken = loginResult['refresh_token'] as String;

      // Extract token ID
      final jwt = JwtHelper.verifyToken(refreshToken);
      final tokenId = int.parse(jwt['jti'] as String);

      // Logout
      final useCase = LogoutUseCase.factory({'refresh_token': refreshToken});
      await useCase.execute();

      // Verify token still exists in database
      final tokenRecord = await db.queryOne(
        '''
        SELECT id, id_user, token_hash, revoked, created_at, expires_at
        FROM auth.refresh_token
        WHERE id = @tokenId
        ''',
        {'tokenId': tokenId},
      );

      expect(tokenRecord, isNotNull);
      expect(tokenRecord!['id'], equals(tokenId));
      expect(tokenRecord['revoked'], isTrue);
      expect(tokenRecord['token_hash'], isNotNull);
      expect(tokenRecord['created_at'], isNotNull);
      expect(tokenRecord['expires_at'], isNotNull);

      print('✓ Token still exists in database (soft delete)');
      print('  Token ID: ${tokenRecord['id']}');
      print('  User ID: ${tokenRecord['id_user']}');
      print('  Revoked: ${tokenRecord['revoked']}');
    });

    test('should maintain token audit trail after logout', () async {
      // Login
      final loginResult = await performLogin(db);
      final refreshToken = loginResult['refresh_token'] as String;

      // Extract token ID
      final jwt = JwtHelper.verifyToken(refreshToken);
      final tokenId = int.parse(jwt['jti'] as String);

      // Get token details before logout
      final beforeLogout = await db.queryOne(
        '''
        SELECT id, id_user, created_at, expires_at
        FROM auth.refresh_token
        WHERE id = @tokenId
        ''',
        {'tokenId': tokenId},
      );

      // Logout
      final useCase = LogoutUseCase.factory({'refresh_token': refreshToken});
      await useCase.execute();

      // Get token details after logout
      final afterLogout = await db.queryOne(
        '''
        SELECT id, id_user, created_at, expires_at, revoked
        FROM auth.refresh_token
        WHERE id = @tokenId
        ''',
        {'tokenId': tokenId},
      );

      // Verify audit trail is maintained
      expect(afterLogout!['id'], equals(beforeLogout!['id']));
      expect(afterLogout['id_user'], equals(beforeLogout['id_user']));
      expect(afterLogout['created_at'], equals(beforeLogout['created_at']));
      expect(afterLogout['expires_at'], equals(beforeLogout['expires_at']));
      expect(afterLogout['revoked'], isTrue);

      print('✓ Token audit trail maintained after logout');
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
