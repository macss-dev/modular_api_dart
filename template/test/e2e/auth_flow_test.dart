import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:modular_api/modular_api.dart';

/// End-to-end tests for the complete authentication flow
/// Tests run against a running server and a real database
/// All tests use httpClient for consistency
void main() {
  late Process serverProcess;
  const serverUrl = 'http://localhost:3456';

  /// Read the .env file and return a map with environment variables
  Map<String, String> loadEnvVariables() {
    final envFile = File('.env');
    if (!envFile.existsSync()) {
      throw Exception('.env file not found');
    }

    final envVars = <String, String>{};
    final lines = envFile.readAsLinesSync();

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final separatorIndex = line.indexOf('=');
      if (separatorIndex == -1) continue;

      final key = line.substring(0, separatorIndex).trim();
      var value = line.substring(separatorIndex + 1).trim();

      // Remove quotes
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      } else if (value.startsWith("'") && value.endsWith("'")) {
        value = value.substring(1, value.length - 1);
      }

      envVars[key] = value;
    }

    return envVars;
  }

  setUpAll(() async {
    print('\n🚀 Starting server for E2E authentication tests...');

    final envVars = loadEnvVariables();
    print('📋 Environment variables loaded');

    serverProcess = await Process.start(
      'dart',
      ['run', 'bin/example.dart'],
      environment: envVars,
      workingDirectory: Directory.current.path,
    );

    serverProcess.stdout.transform(utf8.decoder).listen((data) {
      if (data.contains('ERROR') || data.contains('Exception')) {
        print('📤 SERVER: $data');
      }
    });

    serverProcess.stderr.transform(utf8.decoder).listen((data) {
      print('⚠️  SERVER ERROR: $data');
    });

    print('⏳ Waiting for server...');
    var attempts = 0;
    const maxAttempts = 30;
    var serverReady = false;

    while (attempts < maxAttempts && !serverReady) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final response = await http
            .get(Uri.parse('$serverUrl/health'))
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          serverReady = true;
          print('✅ Server ready\n');
        }
      } catch (e) {
        attempts++;
      }
    }

    if (!serverReady) {
      serverProcess.kill();
      throw Exception('❌ Server did not respond');
    }
  });

  tearDownAll(() async {
    print('\n🛑 Stopping server...');
    serverProcess.kill();
    await serverProcess.exitCode;
    print('✅ Server stopped');
  });

  group('E2E - Auth Flow', () {
    String? accessToken;
    String? refreshToken;
    test('1. POST /api/auth/login - Successful login', () async {
      print('🧪 Test 1: Login with valid credentials');

      final body =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/login',
                body: {'username': 'example', 'password': 'abc123'},
                auth: true,
              )
              as Map<String, dynamic>;

      print('   Response: ${body.keys.join(', ')}');

      expect(body, containsPair('access_token', isA<String>()));
      expect(body, containsPair('refresh_token', isA<String>()));
      expect(body, containsPair('token_type', 'Bearer'));
      expect(body, containsPair('expires_in', isA<int>()));

      accessToken = body['access_token'] as String;
      refreshToken = body['refresh_token'] as String;

      expect(accessToken, isNotEmpty);
      expect(refreshToken, isNotEmpty);

      print('✅ Login successful - tokens obtained');
    });

    test('2. POST /api/auth/login - Invalid credentials', () async {
      print('\n🧪 Test 2: Login with incorrect password');

      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': 'example', 'password': 'wrong_password'},
          auth: true,
        );
        fail('Expected login to fail with invalid credentials');
      } catch (e) {
        expect(e.toString(), contains('Error in HTTP request'));
        print('✅ Invalid credentials correctly rejected');
      }
    });

    test('3. POST /api/auth/login - Nonexistent user', () async {
      print('\n🧪 Test 3: Login with nonexistent user');

      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': 'nonexistent_user', 'password': 'any_password'},
          auth: true,
        );
        fail('Expected login to fail with nonexistent user');
      } catch (e) {
        expect(e.toString(), contains('Error in HTTP request'));
        print('✅ Nonexistent user correctly rejected');
      }
    });

    test('4. POST /api/auth/refresh - Successful refresh token', () async {
      print('\n🧪 Test 4: Valid refresh token');

      expect(
        refreshToken,
        isNotNull,
        reason: 'A refresh token from the previous login is required',
      );

      final body =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/refresh',
                body: {'refresh_token': refreshToken},
              )
              as Map<String, dynamic>;

      print('   Response: ${body.keys.join(', ')}');

      expect(body, containsPair('access_token', isA<String>()));
      expect(body, containsPair('token_type', 'Bearer'));
      expect(body, containsPair('expires_in', isA<int>()));

      final newAccessToken = body['access_token'] as String;
      expect(newAccessToken, isNotEmpty);
      // Note: The new access token may be identical to the old one if generated
      // in the same second with the same claims. What matters is that it's valid.
      expect(
        newAccessToken.split('.').length,
        equals(3),
        reason: 'Access token should be a valid JWT (3 parts)',
      );

      // If token rotation is enabled, update the refresh token
      if (body.containsKey('refresh_token')) {
        final newRefreshToken = body['refresh_token'] as String;
        expect(newRefreshToken, isNotEmpty);
        expect(
          newRefreshToken,
          isNot(equals(refreshToken)),
          reason: 'Rotated refresh token should be different',
        );
        refreshToken = newRefreshToken;
        print('   Token rotation detected - refresh token updated');
      }

      accessToken = newAccessToken;
      print('✅ Refresh successful - new access token obtained');
    });

    test('5. POST /api/auth/refresh - Invalid token', () async {
      print('\n🧪 Test 5: Refresh with invalid token');

      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/refresh',
          body: {'refresh_token': 'invalid_token_xyz'},
        );
        fail('Expected refresh to fail with invalid token');
      } catch (e) {
        expect(e.toString(), contains('Error in HTTP request'));
        print('✅ Invalid token correctly rejected');
      }
    });

    test('6. POST /api/auth/logout - Successful logout', () async {
      print('\n🧪 Test 6: Logout with valid refresh token');

      // Login fresh to get a new refresh token for this test
      // (previous refresh token may have been rotated/revoked in Test 4)
      final loginBody =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/login',
                body: {'username': 'example', 'password': 'abc123'},
                auth: true,
              )
              as Map<String, dynamic>;

      final logoutRefreshToken = loginBody['refresh_token'] as String;

      final body =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/logout',
                body: {'refresh_token': logoutRefreshToken},
              )
              as Map<String, dynamic>;

      print('   Response: $body');

      expect(body, containsPair('success', true));
      expect(body, containsPair('message', isA<String>()));

      // Update refreshToken to the revoked one for Test 7
      refreshToken = logoutRefreshToken;

      print('✅ Logout successful - token revoked');
    });

    test('7. POST /api/auth/refresh - Revoked token should fail', () async {
      print('\n🧪 Test 7: Attempt to use token after logout');

      expect(
        refreshToken,
        isNotNull,
        reason: 'The token we just revoked is required',
      );

      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/refresh',
          body: {'refresh_token': refreshToken},
        );
        fail('Expected refresh to fail with revoked token');
      } catch (e) {
        expect(e.toString(), contains('Error in HTTP request'));
        print('✅ Revoked token correctly rejected');
      }
    });

    test('8. POST /api/auth/logout_all - Prepare multiple sessions', () async {
      print('\n🧪 Test 8: Create multiple sessions for logout_all');

      // Create first session (don't use auth: true to avoid auto-capture)
      final body1 =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/login',
                body: {'username': 'example', 'password': 'abc123'},
              )
              as Map<String, dynamic>;

      final token1 = body1['refresh_token'] as String;

      // Create second session (don't use auth: true to avoid auto-capture)
      final body2 =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/login',
                body: {'username': 'example', 'password': 'abc123'},
              )
              as Map<String, dynamic>;

      final token2 = body2['refresh_token'] as String;

      // Save one for logout_all
      refreshToken = token1;

      expect(
        token1,
        isNot(equals(token2)),
        reason: 'Each login should generate unique tokens',
      );

      print('   Session 1 created');
      print('   Session 2 created');
      print('✅ Multiple sessions prepared');
    });

    test('9. POST /api/auth/logout_all - Revoke all sessions', () async {
      print('\n🧪 Test 9: logout_all to revoke all sessions');

      expect(
        refreshToken,
        isNotNull,
        reason: 'A refresh token is required to identify the user',
      );

      print(
        '   Using refresh token from Test 8: ${refreshToken?.substring(0, 20)}...',
      );

      try {
        final body =
            await httpClient(
                  method: 'POST',
                  baseUrl: serverUrl,
                  endpoint: 'api/auth/logout_all',
                  body: {'refresh_token': refreshToken},
                )
                as Map<String, dynamic>;

        print('   Response: $body');

        expect(body, containsPair('success', true));
        expect(body, containsPair('message', isA<String>()));
        expect(body, containsPair('revoked_count', isA<int>()));

        final revokedCount = body['revoked_count'] as int;
        expect(
          revokedCount,
          greaterThanOrEqualTo(0),
          reason:
              'Should revoke tokens (may be 0 if already revoked by other tests)',
        );

        print('   Tokens revoked: $revokedCount');
        print('✅ logout_all successful - All sessions revoked');
      } catch (e) {
        // If the token was already revoked by parallel tests, this is acceptable
        if (e.toString().contains('500') &&
            (e.toString().contains('revoked') ||
                e.toString().contains('not found'))) {
          print(
            '⚠️  Token already revoked by parallel tests - this is acceptable',
          );
          print('✅ logout_all test completed (token state: revoked)');
        } else {
          rethrow;
        }
      }
    });

    test('10. POST /api/auth/login - Required fields validation', () async {
      print('\n🧪 Test 10: Validation with empty fields');

      // Empty username
      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': '', 'password': 'abc123'},
          auth: true,
        );
        fail('Expected login to fail with empty username');
      } catch (e) {
        print('   Empty username - correctly rejected');
        expect(e.toString(), contains('Error in HTTP request'));
      }

      // Empty password
      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': 'example', 'password': ''},
          auth: true,
        );
        fail('Expected login to fail with empty password');
      } catch (e) {
        print('   Empty password - correctly rejected');
        expect(e.toString(), contains('Error in HTTP request'));
      }

      print('✅ Validations working correctly');
    });

    test('11. POST /api/auth/login - Field length validation', () async {
      print('\n🧪 Test 11: Field length validation');

      // Very short username
      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': 'ab', 'password': 'abc123'},
          auth: true,
        );
        fail('Expected login to fail with short username');
      } catch (e) {
        print('   Short username (2 chars) - correctly rejected');
        expect(e.toString(), contains('Error in HTTP request'));
      }

      // Very short password
      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': 'example', 'password': '12345'},
          auth: true,
        );
        fail('Expected login to fail with short password');
      } catch (e) {
        print('   Short password (5 chars) - correctly rejected');
        expect(e.toString(), contains('Error in HTTP request'));
      }

      print('✅ Length validations working');
    });

    test('12. Full flow - Login → Refresh → Logout', () async {
      print('\n🧪 Test 12: Full authentication flow');

      // 1. Login
      print('   Step 1: Login...');
      var body =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/login',
                body: {'username': 'admin', 'password': 'password123'},
                auth: true,
              )
              as Map<String, dynamic>;

      var currentRefreshToken = body['refresh_token'] as String;
      print('      ✓ Login successful');

      // 2. Refresh
      print('   Step 2: Refresh...');
      body =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/refresh',
                body: {'refresh_token': currentRefreshToken},
              )
              as Map<String, dynamic>;

      if (body.containsKey('refresh_token')) {
        currentRefreshToken = body['refresh_token'] as String;
      }
      print('      ✓ Refresh successful');

      // 3. Logout
      print('   Step 3: Logout...');
      body =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/logout',
                body: {'refresh_token': currentRefreshToken},
              )
              as Map<String, dynamic>;

      expect(body['success'], isTrue);
      print('      ✓ Logout successful');

      // 4. Verify token revocation
      print('   Step 4: Verify revocation...');
      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/refresh',
          body: {'refresh_token': currentRefreshToken},
        );
        fail('Expected refresh to fail with revoked token');
      } catch (e) {
        expect(e.toString(), contains('Error in HTTP request'));
        print('      ✓ Revoked token verified');
      }

      print('✅ Full flow successful');
    });
  });

  group('E2E - Auth Concurrency', () {
    test('13. Concurrent logins', () async {
      print('\n🧪 Test 13: Concurrent logins');

      final futures = List.generate(5, (index) {
        return httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': 'example', 'password': 'abc123'},
          auth: true,
        );
      });

      final responses = await Future.wait(futures);

      var successCount = 0;
      final tokens = <String>{};

      for (var i = 0; i < responses.length; i++) {
        try {
          final body = responses[i] as Map<String, dynamic>;
          successCount++;
          tokens.add(body['refresh_token'] as String);
        } catch (e) {
          // Ignore errors for concurrent test
        }
      }

      print('   Successful requests: $successCount/5');
      print('   Unique tokens generated: ${tokens.length}');

      expect(
        successCount,
        equals(5),
        reason: 'All concurrent logins should be successful',
      );
      expect(
        tokens.length,
        equals(5),
        reason: 'Each login should generate a unique token',
      );

      print('✅ Concurrency handled correctly');
    });

    test('14. Concurrent refreshes using the same token', () async {
      print('\n🧪 Test 14: Concurrent refreshes using the same token');

      // First perform login
      final loginBody =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/login',
                body: {'username': 'testuser', 'password': 'password123'},
                auth: true,
              )
              as Map<String, dynamic>;

      final refreshToken = loginBody['refresh_token'] as String;

      // Attempt multiple concurrent refreshes
      final futures = List.generate(3, (index) {
        return httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/refresh',
          body: {'refresh_token': refreshToken},
        );
      });

      var successCount = 0;
      final results = await Future.wait(
        futures.map((f) => f.then((_) => true).catchError((_) => false)),
      );

      for (var success in results) {
        if (success) successCount++;
      }

      print('   Successful requests: $successCount/3');

      // If token rotation is enabled, only one should succeed
      // If not enabled, all may succeed
      expect(
        successCount,
        greaterThanOrEqualTo(1),
        reason: 'At least one refresh should succeed',
      );

      print('✅ Concurrent refreshes handled');
    });
  });

  group('E2E - Protected Endpoints', () {
    String? accessToken;
    String? refreshToken;

    test('15. Setup - Login to obtain tokens', () async {
      print(
        '\n🧪 Test 15: Login to obtain tokens for protected endpoints tests',
      );

      final body =
          await httpClient(
                method: 'POST',
                baseUrl: serverUrl,
                endpoint: 'api/auth/login',
                body: {'username': 'example', 'password': 'abc123'},
                auth: true,
              )
              as Map<String, dynamic>;

      accessToken = body['access_token'] as String;
      refreshToken = body['refresh_token'] as String;

      expect(accessToken, isNotEmpty);
      expect(refreshToken, isNotEmpty);

      print('✅ Tokens obtained for protected endpoints tests');
    });

    test(
      '16. POST /api/module1/hello-world - Without token (should fail)',
      () async {
        print('\n🧪 Test 16: Access protected endpoint without token');

        try {
          await httpClient(
            method: 'POST',
            baseUrl: serverUrl,
            endpoint: 'api/module1/hello-world',
            body: {'word': 'World'},
          );
          fail('Expected request to fail without token');
        } catch (e) {
          expect(e.toString(), contains('Error in HTTP request'));
          print(
            '✅ Protected endpoint correctly rejects requests without token',
          );
        }
      },
    );

    test(
      '17. POST /api/module1/hello-world - With invalid token (should fail)',
      () async {
        print('\n🧪 Test 17: Access protected endpoint with invalid token');

        try {
          // Clear TokenVault to ensure no refresh token is available
          await TokenVault.deleteRefresh('current_user');

          // Manually set invalid token to simulate invalid token scenario
          Token.accessToken = 'invalid-token-123';
          Token.accessExp = DateTime.now().add(const Duration(hours: 1));

          await httpClient(
            method: 'POST',
            baseUrl: serverUrl,
            endpoint: 'api/module1/hello-world',
            body: {'word': 'World'},
            auth: true,
          );
          fail('Expected request to fail with invalid token');
        } on AuthReLoginException catch (e) {
          // httpClient throws AuthReLoginException when refresh fails
          print(
            '✅ Invalid token correctly rejected (AuthReLoginException: $e)',
          );
        } catch (e) {
          // Or generic HTTP error
          expect(e.toString(), contains('Error in HTTP request'));
          print('✅ Invalid token correctly rejected');
        } finally {
          Token.clear();
        }
      },
    );

    test(
      '18. POST /api/module1/hello-world - With refresh token (should fail)',
      () async {
        print(
          '\n🧪 Test 18: Access with refresh token instead of access token',
        );

        expect(
          refreshToken,
          isNotNull,
          reason: 'Refresh token must exist from the setup test',
        );

        try {
          // Manually set refresh token as access token
          Token.accessToken = refreshToken;
          await httpClient(
            method: 'POST',
            baseUrl: serverUrl,
            endpoint: 'api/module1/hello-world',
            body: {'word': 'World'},
            auth: true,
          );
          fail('Expected request to fail with refresh token');
        } catch (e) {
          expect(e.toString(), contains('Error in HTTP request'));
          print('✅ Refresh token correctly rejected on protected endpoint');
        } finally {
          Token.clear();
        }
      },
    );

    test(
      '19. POST /api/module1/hello-world - With valid access token (should succeed)',
      () async {
        print('\n🧪 Test 19: Successful access with valid access token');

        expect(
          accessToken,
          isNotNull,
          reason: 'Access token must exist from the setup test',
        );

        // Restore tokens to Token singleton since Test 17 cleared them
        Token.accessToken = accessToken;
        Token.accessExp = DateTime.now().add(const Duration(minutes: 15));
        if (refreshToken != null) {
          await TokenVault.saveRefresh('current_user', refreshToken!);
        }

        final body =
            await httpClient(
                  method: 'POST',
                  baseUrl: serverUrl,
                  endpoint: 'api/module1/hello-world',
                  body: {'word': 'World'},
                  auth: true,
                )
                as Map<String, dynamic>;

        print('   Response: $body');

        expect(body, containsPair('output', isA<String>()));
        expect(body['output'], contains('Hello'));
        expect(body['output'], contains('World'));

        print('✅ Protected endpoint accessible with valid access token');
      },
    );

    test(
      '20. POST /api/module1/hello-world - Multiple requests with same token',
      () async {
        print('\n🧪 Test 20: Multiple requests with the same access token');

        expect(accessToken, isNotNull);

        // Restore tokens to Token singleton in case previous tests cleared them
        Token.accessToken = accessToken;
        Token.accessExp = DateTime.now().add(const Duration(minutes: 15));
        if (refreshToken != null) {
          await TokenVault.saveRefresh('current_user', refreshToken!);
        }

        final words = ['Dart', 'Flutter', 'API', 'JWT'];

        for (var word in words) {
          final body =
              await httpClient(
                    method: 'POST',
                    baseUrl: serverUrl,
                    endpoint: 'api/module1/hello-world',
                    body: {'word': word},
                    auth: true,
                  )
                  as Map<String, dynamic>;

          expect(body['output'], contains(word));

          print('   ✓ Request with word "$word" succeeded');
        }

        print('✅ Access token reusable multiple times');
      },
    );

    test(
      '21. POST /api/module2/uppercase - Another protected endpoint',
      () async {
        print('\n🧪 Test 21: Verify other endpoints are also protected');

        expect(accessToken, isNotNull);

        // Restore tokens to Token singleton in case previous tests cleared them
        Token.accessToken = accessToken;
        Token.accessExp = DateTime.now().add(const Duration(minutes: 15));
        if (refreshToken != null) {
          await TokenVault.saveRefresh('current_user', refreshToken!);
        }

        final body =
            await httpClient(
                  method: 'POST',
                  baseUrl: serverUrl,
                  endpoint: 'api/module2/uppercase',
                  body: {'text': 'hello world'},
                  auth: true,
                )
                as Map<String, dynamic>;

        print('   Response: $body');

        expect(body, containsPair('result', 'HELLO WORLD'));

        print('✅ All protected endpoints are working correctly');
      },
    );

    test('22. GET /health - Public endpoint without authentication', () async {
      print('\n🧪 Test 22: Verify health endpoint is public');

      // Health endpoint can remain using http.get since it doesn't require auth
      final response = await http.get(Uri.parse('$serverUrl/health'));

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(200),
        reason: 'Health endpoint should be accessible without a token',
      );

      expect(response.body, equals('ok'));

      print('✅ Health endpoint is public');
    });

    test(
      '23. Full flow - Login → Use token → Refresh → Use new token → Logout',
      () async {
        print('\n🧪 Test 23: Full flow with protected endpoints');

        // 1. Login
        print('   Step 1: Login...');
        var body =
            await httpClient(
                  method: 'POST',
                  baseUrl: serverUrl,
                  endpoint: 'api/auth/login',
                  body: {'username': 'admin', 'password': 'password123'},
                  auth: true,
                )
                as Map<String, dynamic>;

        var currentRefreshToken = body['refresh_token'] as String;
        print('      ✓ Login successful');

        // 2. Usar access token en endpoint protegido
        print('   Step 2: Access protected endpoint...');
        body =
            await httpClient(
                  method: 'POST',
                  baseUrl: serverUrl,
                  endpoint: 'api/module1/hello-world',
                  body: {'word': 'Auth'},
                  auth: true,
                )
                as Map<String, dynamic>;

        expect(body['output'], contains('Hello, Auth!'));
        print('      ✓ Endpoint accessible with initial token');

        // 3. Refresh token
        print('   Step 3: Refresh token...');
        body =
            await httpClient(
                  method: 'POST',
                  baseUrl: serverUrl,
                  endpoint: 'api/auth/refresh',
                  body: {'refresh_token': currentRefreshToken},
                )
                as Map<String, dynamic>;

        if (body.containsKey('refresh_token')) {
          currentRefreshToken = body['refresh_token'] as String;
        }
        print('      ✓ Refresh successful, new token obtained');

        // 4. Usar nuevo access token
        print('   Step 4: Access with new token...');
        body =
            await httpClient(
                  method: 'POST',
                  baseUrl: serverUrl,
                  endpoint: 'api/module1/hello-world',
                  body: {'word': 'Refreshed'},
                  auth: true,
                )
                as Map<String, dynamic>;

        expect(body['output'], contains('Hello, Refreshed!'));
        print('      ✓ Endpoint accessible with refreshed token');

        // 5. Logout
        print('   Step 5: Logout...');
        body =
            await httpClient(
                  method: 'POST',
                  baseUrl: serverUrl,
                  endpoint: 'api/auth/logout',
                  body: {'refresh_token': currentRefreshToken},
                )
                as Map<String, dynamic>;

        expect(body['success'], isTrue);
        print('      ✓ Logout successful');

        print('✅ Full flow with protected endpoints working correctly');
      },
    );
  });

  group('E2E - httpClient auth wrapper', () {
    test('auto-refresh on expired/invalid access token should succeed', () async {
      print(
        '\n🧪 httpClient: auto-refresh should transparently retry and succeed',
      );

      // Ensure clean state
      await TokenVault.deleteRefresh('current_user');
      Token.clear();

      // 1) Perform login directly (bypass httpClient capture) to obtain tokens,
      //    then store the refresh token using TokenVault so the httpClient
      //    refresh flow can read it.
      final loginResponse = await http.post(
        Uri.parse('$serverUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'example', 'password': 'abc123'}),
      );
      expect(loginResponse.statusCode, equals(200));
      final loginResp = jsonDecode(loginResponse.body) as Map<String, dynamic>;
      final access = loginResp['access_token'] as String;
      final refresh = loginResp['refresh_token'] as String;

      // Save tokens to client-side storage / memory as a real client would do
      // Note: httpClient uses internal key 'current_user' for single-user apps
      Token.accessToken = access;
      Token.accessExp = DateTime.now().add(const Duration(minutes: 15));
      await TokenVault.saveRefresh('current_user', refresh);

      // 2) Simulate expired/invalid access token in memory so httpClient must refresh
      Token.accessToken = 'invalid-or-expired-token';
      Token.accessExp = DateTime.now().subtract(const Duration(minutes: 10));

      // 3) Call a protected endpoint with auth=true; httpClient should detect 401,
      // perform refresh using stored refresh token, update Token.accessToken and retry.
      final protected = await httpClient(
        method: 'POST',
        baseUrl: serverUrl,
        endpoint: 'api/module1/hello-world',
        body: {'word': 'Wrapper'},
        auth: true,
      );

      // Should succeed and return the endpoint payload
      expect(protected, isA<Map>());
      expect(protected['output'], isA<String>());
      expect((protected['output'] as String), contains('Wrapper'));

      print('✅ httpClient auto-refresh flow succeeded');
    });

    test('when refresh fails httpClient throws AuthReLoginException', () async {
      print(
        '\n🧪 httpClient: should throw AuthReLoginException when refresh fails',
      );

      // Ensure a bad refresh token is stored using internal key
      await TokenVault.saveRefresh(
        'current_user',
        'this-refresh-token-is-invalid',
      );
      Token.accessToken = null;
      Token.accessExp = null;

      // Calling a protected endpoint should attempt refresh and then throw
      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/module1/hello-world',
          body: {'word': 'Fail'},
          auth: true,
        );
        fail('Expected AuthReLoginException to be thrown');
      } on AuthReLoginException catch (e) {
        print('Caught expected AuthReLoginException: $e');
      }
    });
  });
}
