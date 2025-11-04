import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:modular_api/modular_api.dart';

/// End-to-end tests for the complete authentication flow
/// Tests run against a running server and a real database
void main() {
  late Process serverProcess;
  const serverUrl = 'http://localhost:3456';
  const baseApiUrl = '$serverUrl/api';

  /// Lee el archivo .env y retorna un mapa con las variables de entorno
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

      // Remover comillas
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
      throw Exception('❌ Servidor no respondió');
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

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'example', 'password': 'abc123'}),
      );

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(200),
        reason: 'Login should return 200 OK',
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
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

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'example', 'password': 'wrong_password'}),
      );

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(500),
        reason: 'Login with invalid credentials should fail',
      );

      print('✅ Invalid credentials correctly rejected');
    });

    test('3. POST /api/auth/login - Nonexistent user', () async {
      print('\n🧪 Test 3: Login with nonexistent user');

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': 'nonexistent_user',
          'password': 'any_password',
        }),
      );

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(500),
        reason: 'Login with nonexistent user should fail',
      );

      print('✅ Nonexistent user correctly rejected');
    });

    test('4. POST /api/auth/refresh - Successful refresh token', () async {
      print('\n🧪 Test 4: Valid refresh token');

      expect(
        refreshToken,
        isNotNull,
        reason: 'Se necesita refresh token del login anterior',
      );

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

  print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(200),
        reason: 'Refresh should return 200 OK',
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
  print('   Response: ${body.keys.join(', ')}');

      expect(body, containsPair('access_token', isA<String>()));
      expect(body, containsPair('token_type', 'Bearer'));
      expect(body, containsPair('expires_in', isA<int>()));

      final newAccessToken = body['access_token'] as String;
      expect(newAccessToken, isNotEmpty);
      // Note: The new access token may be identical to the old one if generated
      // in the same second with the same claims. What matters is that it's valid.
      expect(newAccessToken.split('.').length, equals(3), reason: 'Access token debe ser un JWT válido (3 partes)');

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

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': 'invalid_token_xyz'}),
      );

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(500),
        reason: 'Refresh with invalid token should fail',
      );

      print('✅ Invalid token correctly rejected');
    });

    test('6. POST /api/auth/logout - Successful logout', () async {
      print('\n🧪 Test 6: Logout with valid refresh token');

      // Login fresh to get a new refresh token for this test
      // (previous refresh token may have been rotated/revoked in Test 4)
      final loginResponse = await http.post(
        Uri.parse('$baseApiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'example', 'password': 'abc123'}),
      );
      expect(loginResponse.statusCode, equals(200));
      final loginBody = jsonDecode(loginResponse.body) as Map<String, dynamic>;
      final logoutRefreshToken = loginBody['refresh_token'] as String;

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': logoutRefreshToken}),
      );

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(200),
        reason: 'Logout should return 200 OK',
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
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

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(500),
        reason: 'Refresh with revoked token should fail',
      );

      print('✅ Revoked token correctly rejected');
    });

    test(
      '8. POST /api/auth/logout_all - Preparar múltiples sesiones',
      () async {
  print('\n🧪 Test 8: Create multiple sessions for logout_all');

        // Crear primera sesión
        final response1 = await http.post(
          Uri.parse('$baseApiUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': 'example', 'password': 'abc123'}),
        );

        expect(response1.statusCode, equals(200));
        final body1 = jsonDecode(response1.body) as Map<String, dynamic>;
        final token1 = body1['refresh_token'] as String;

        // Crear segunda sesión
        final response2 = await http.post(
          Uri.parse('$baseApiUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': 'example', 'password': 'abc123'}),
        );

        expect(response2.statusCode, equals(200));
        final body2 = jsonDecode(response2.body) as Map<String, dynamic>;
        final token2 = body2['refresh_token'] as String;

        // Guardar uno para logout_all
        refreshToken = token1;

        expect(
          token1,
          isNot(equals(token2)),
          reason: 'Each login should generate unique tokens',
        );

        print('   Session 1 created');
        print('   Session 2 created');
        print('✅ Multiple sessions prepared');
      },
    );

    test('9. POST /api/auth/logout_all - Revocar todas las sesiones', () async {
      print('\n🧪 Test 9: Logout_all para revocar todas las sesiones');

      expect(
        refreshToken,
        isNotNull,
        reason: 'Se necesita refresh token para identificar usuario',
      );

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/logout_all'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(200),
        reason: 'Logout_all debe retornar 200 OK',
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      print('   Response: $body');

      expect(body, containsPair('success', true));
      expect(body, containsPair('message', isA<String>()));
      expect(body, containsPair('revoked_count', isA<int>()));

      final revokedCount = body['revoked_count'] as int;
      expect(
        revokedCount,
        greaterThanOrEqualTo(2),
        reason: 'Debe revocar al menos las 2 sesiones creadas',
      );

      print('   Tokens revocados: $revokedCount');
      print('✅ Logout_all exitoso - Todas las sesiones revocadas');
    });

    test(
      '10. POST /api/auth/login - Validación de campos requeridos',
      () async {
    print('\n🧪 Test 10: Validation with empty fields');

        // Username vacío
        var response = await http.post(
          Uri.parse('$baseApiUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': '', 'password': 'abc123'}),
        );

  print('   Empty username - Status: ${response.statusCode}');
        expect(
          response.statusCode,
          equals(400),
          reason: 'Username vacío debe ser rechazado',
        );

        // Password vacío
        response = await http.post(
          Uri.parse('$baseApiUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': 'example', 'password': ''}),
        );

  print('   Empty password - Status: ${response.statusCode}');
        expect(
          response.statusCode,
          equals(400),
          reason: 'Password vacío debe ser rechazado',
        );

        print('✅ Validations working correctly');
      },
    );

    test(
      '11. POST /api/auth/login - Validación de longitud de campos',
      () async {
  print('\n🧪 Test 11: Field length validation');

        // Username muy corto
        var response = await http.post(
          Uri.parse('$baseApiUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': 'ab', 'password': 'abc123'}),
        );

  print('   Short username (2 chars) - Status: ${response.statusCode}');
        expect(
          response.statusCode,
          equals(400),
          reason: 'Username muy corto debe ser rechazado',
        );

        // Password muy corto
        response = await http.post(
          Uri.parse('$baseApiUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': 'example', 'password': '12345'}),
        );

  print('   Short password (5 chars) - Status: ${response.statusCode}');
        expect(
          response.statusCode,
          equals(400),
          reason: 'Password muy corto debe ser rechazado',
        );

        print('✅ Length validations working');
      },
    );

    test('12. Flujo completo - Login → Refresh → Logout', () async {
  print('\n🧪 Test 12: Full authentication flow');

      // 1. Login
  print('   Step 1: Login...');
      var response = await http.post(
        Uri.parse('$baseApiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'admin', 'password': 'password123'}),
      );

      expect(response.statusCode, equals(200));
      var body = jsonDecode(response.body) as Map<String, dynamic>;
      // var currentAccessToken = body['access_token'] as String;
      var currentRefreshToken = body['refresh_token'] as String;
  print('      ✓ Login successful');

      // 2. Refresh
  print('   Step 2: Refresh...');
      response = await http.post(
        Uri.parse('$baseApiUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': currentRefreshToken}),
      );

      expect(response.statusCode, equals(200));
      body = jsonDecode(response.body) as Map<String, dynamic>;
      // currentAccessToken = body['access_token'] as String;
      if (body.containsKey('refresh_token')) {
        currentRefreshToken = body['refresh_token'] as String;
      }
  print('      ✓ Refresh successful');

      // 3. Logout
  print('   Step 3: Logout...');
      response = await http.post(
        Uri.parse('$baseApiUrl/auth/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': currentRefreshToken}),
      );

      expect(response.statusCode, equals(200));
      body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['success'], isTrue);
  print('      ✓ Logout successful');

      // 4. Verificar token revocado
  print('   Step 4: Verify revocation...');
      response = await http.post(
        Uri.parse('$baseApiUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': currentRefreshToken}),
      );

      expect(response.statusCode, equals(500));
  print('      ✓ Revoked token verified');

      print('✅ Full flow successful');
    });
  });

  group('E2E - Auth Concurrency', () {
    test('13. Múltiples logins simultáneos', () async {
  print('\n🧪 Test 13: Concurrent logins');

      final futures = List.generate(5, (index) {
        return http.post(
          Uri.parse('$baseApiUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': 'example', 'password': 'abc123'}),
        );
      });

      final responses = await Future.wait(futures);

      var successCount = 0;
      final tokens = <String>{};

      for (var i = 0; i < responses.length; i++) {
        final response = responses[i];
        if (response.statusCode == 200) {
          successCount++;
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          tokens.add(body['refresh_token'] as String);
        }
      }

  print('   Successful requests: $successCount/5');
  print('   Unique tokens generated: ${tokens.length}');

      expect(
        successCount,
        equals(5),
        reason: 'Todos los logins concurrentes deben ser exitosos',
      );
      expect(
        tokens.length,
        equals(5),
        reason: 'Cada login debe generar un token único',
      );

      print('✅ Concurrency handled correctly');
    });

    test('14. Múltiples refreshes simultáneos del mismo token', () async {
  print('\n🧪 Test 14: Concurrent refreshes using the same token');

      // Primero hacer login
      final loginResponse = await http.post(
        Uri.parse('$baseApiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'testuser', 'password': 'password123'}),
      );

      expect(loginResponse.statusCode, equals(200));
      final loginBody = jsonDecode(loginResponse.body) as Map<String, dynamic>;
      final refreshToken = loginBody['refresh_token'] as String;

      // Intentar múltiples refreshes simultáneos
      final futures = List.generate(3, (index) {
        return http.post(
          Uri.parse('$baseApiUrl/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        );
      });

      final responses = await Future.wait(futures);

      var successCount = 0;
      for (var response in responses) {
        if (response.statusCode == 200) {
          successCount++;
        }
      }

  print('   Successful requests: $successCount/3');

      // Si hay token rotation, solo uno debería tener éxito
      // Si no hay rotation, todos deberían tener éxito
      expect(
        successCount,
        greaterThanOrEqualTo(1),
        reason: 'Al menos un refresh debe ser exitoso',
      );

      print('✅ Concurrent refreshes handled');
    });
  });

  group('E2E - Protected Endpoints', () {
    String? accessToken;
    String? refreshToken;

    test('15. Setup - Login para obtener tokens', () async {
  print('\n🧪 Test 15: Login to obtain tokens for protected endpoints tests');

      final response = await http.post(
        Uri.parse('$baseApiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'example', 'password': 'abc123'}),
      );

      expect(response.statusCode, equals(200));
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      accessToken = body['access_token'] as String;
      refreshToken = body['refresh_token'] as String;

      expect(accessToken, isNotEmpty);
      expect(refreshToken, isNotEmpty);

      print('✅ Tokens obtained for protected endpoints tests');
    });

    test(
      '16. POST /api/module1/hello-world - Sin token (debe fallar)',
      () async {
  print('\n🧪 Test 16: Access protected endpoint without token');

        final response = await http.post(
          Uri.parse('$baseApiUrl/module1/hello-world'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'word': 'World'}),
        );

        print('   Status: ${response.statusCode}');

        expect(
          response.statusCode,
          equals(401),
          reason: 'Should return 401 Unauthorized without token',
        );

        final body = response.body;
        expect(
          body,
          contains('authorization'),
          reason: 'Message should mention authorization',
        );

        print('✅ Protected endpoint correctly rejects requests without token');
      },
    );

    test(
      '17. POST /api/module1/hello-world - Con token inválido (debe fallar)',
      () async {
  print('\n🧪 Test 17: Access protected endpoint with invalid token');

        final response = await http.post(
          Uri.parse('$baseApiUrl/module1/hello-world'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer invalid-token-123',
          },
          body: jsonEncode({'word': 'World'}),
        );

        print('   Status: ${response.statusCode}');

        expect(
          response.statusCode,
          equals(401),
          reason: 'Should return 401 Unauthorized with invalid token',
        );

        final body = response.body;
        expect(
          body,
          contains('Invalid token'),
          reason: 'Message should indicate invalid token',
        );

        print('✅ Invalid token correctly rejected');
      },
    );

    test(
      '18. POST /api/module1/hello-world - Con refresh token (debe fallar)',
      () async {
        print('\n🧪 Test 18: Access with refresh token instead of access token');

        expect(
          refreshToken,
          isNotNull,
          reason: 'Refresh token debe existir del test de setup',
        );

        final response = await http.post(
          Uri.parse('$baseApiUrl/module1/hello-world'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $refreshToken',
          },
          body: jsonEncode({'word': 'World'}),
        );

        print('   Status: ${response.statusCode}');

        expect(
          response.statusCode,
          equals(403),
          reason: 'Should return 403 Forbidden when using refresh token',
        );

        final body = response.body;
        expect(
          body,
          contains('Invalid token type'),
          reason: 'Message should indicate incorrect token type',
        );

        print('✅ Refresh token correctly rejected on protected endpoint');
      },
    );

    test(
      '19. POST /api/module1/hello-world - Con access token válido (debe funcionar)',
      () async {
  print('\n🧪 Test 19: Successful access with valid access token');

        expect(
          accessToken,
          isNotNull,
          reason: 'Access token debe existir del test de setup',
        );

        final response = await http.post(
          Uri.parse('$baseApiUrl/module1/hello-world'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({'word': 'World'}),
        );

        print('   Status: ${response.statusCode}');

        expect(
          response.statusCode,
          equals(200),
          reason: 'Should return 200 OK with valid access token',
        );

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        print('   Response: $body');

        expect(body, containsPair('output', isA<String>()));
        expect(body['output'], contains('Hello'));
        expect(body['output'], contains('World'));

        print('✅ Protected endpoint accessible with valid access token');
      },
    );

    test(
      '20. POST /api/module1/hello-world - Múltiples requests con mismo token',
      () async {
  print('\n🧪 Test 20: Multiple requests with the same access token');

        expect(accessToken, isNotNull);

        final words = ['Dart', 'Flutter', 'API', 'JWT'];

        for (var word in words) {
          final response = await http.post(
            Uri.parse('$baseApiUrl/module1/hello-world'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({'word': word}),
          );

          expect(
            response.statusCode,
            equals(200),
            reason: 'Cada request con el mismo token debe ser exitoso',
          );

          final body = jsonDecode(response.body) as Map<String, dynamic>;
          expect(body['output'], contains(word));

            print('   ✓ Request with word "$word" succeeded');
        }

        print('✅ Access token reusable multiple times');
      },
    );

    test('21. POST /api/module2/uppercase - Otro endpoint protegido', () async {
      print('\n🧪 Test 21: Verify other endpoints are also protected');

      expect(accessToken, isNotNull);

      final response = await http.post(
        Uri.parse('$baseApiUrl/module2/uppercase'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'text': 'hello world'}),
      );

      print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(200),
        reason:
            'Endpoint module2/uppercase debe estar protegido y accesible con token',
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      print('   Response: $body');

      expect(body, containsPair('result', 'HELLO WORLD'));

      print('✅ All protected endpoints are working correctly');
    });

    test('22. GET /health - Endpoint público sin autenticación', () async {
  print('\n🧪 Test 22: Verify health endpoint is public');

      final response = await http.get(Uri.parse('$serverUrl/health'));

  print('   Status: ${response.statusCode}');

      expect(
        response.statusCode,
        equals(200),
        reason: 'Health endpoint debe ser accesible sin token',
      );

      expect(response.body, equals('ok'));

      print('✅ Health endpoint is public');
    });

    test(
      '23. Flujo completo - Login → Usar token → Refresh → Usar nuevo token → Logout',
      () async {
  print('\n🧪 Test 23: Full flow with protected endpoints');

        // 1. Login
  print('   Step 1: Login...');
        var response = await http.post(
          Uri.parse('$baseApiUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': 'admin', 'password': 'password123'}),
        );

        expect(response.statusCode, equals(200));
        var body = jsonDecode(response.body) as Map<String, dynamic>;
        var currentAccessToken = body['access_token'] as String;
        var currentRefreshToken = body['refresh_token'] as String;
  print('      ✓ Login successful');

        // 2. Usar access token en endpoint protegido
  print('   Step 2: Access protected endpoint...');
        response = await http.post(
          Uri.parse('$baseApiUrl/module1/hello-world'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $currentAccessToken',
          },
          body: jsonEncode({'word': 'Auth'}),
        );

        expect(response.statusCode, equals(200));
        body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['output'], contains('Hello, Auth!'));
  print('      ✓ Endpoint accessible with initial token');

        // 3. Refresh token
  print('   Step 3: Refresh token...');
        response = await http.post(
          Uri.parse('$baseApiUrl/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': currentRefreshToken}),
        );

        expect(response.statusCode, equals(200));
        body = jsonDecode(response.body) as Map<String, dynamic>;
        currentAccessToken = body['access_token'] as String;
        if (body.containsKey('refresh_token')) {
          currentRefreshToken = body['refresh_token'] as String;
        }
  print('      ✓ Refresh successful, new token obtained');

        // 4. Usar nuevo access token
  print('   Step 4: Access with new token...');
        response = await http.post(
          Uri.parse('$baseApiUrl/module1/hello-world'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $currentAccessToken',
          },
          body: jsonEncode({'word': 'Refreshed'}),
        );

        expect(response.statusCode, equals(200));
        body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['output'], contains('Hello, Refreshed!'));
  print('      ✓ Endpoint accessible with refreshed token');

        // 5. Logout
  print('   Step 5: Logout...');
        response = await http.post(
          Uri.parse('$baseApiUrl/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': currentRefreshToken}),
        );

        expect(response.statusCode, equals(200));
  print('      ✓ Logout successful');

        print('✅ Full flow with protected endpoints working correctly');
      },
    );
  });

    group('E2E - httpClient auth wrapper', () {
      const clientUser1 = 'httpclient_user_1';
      const clientUser2 = 'httpclient_user_2';

      test('auto-refresh on expired/invalid access token should succeed', () async {
        print('\n🧪 httpClient: auto-refresh should transparently retry and succeed');

        // Ensure clean state
        await TokenVault.deleteRefresh(clientUser1);
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
  Token.accessToken = access;
  Token.accessExp = DateTime.now().add(const Duration(minutes: 15));
  await TokenVault.saveRefresh(clientUser1, refresh);

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
          user: clientUser1,
        );

        // Should succeed and return the endpoint payload
        expect(protected, isA<Map>());
        expect(protected['output'], isA<String>());
        expect((protected['output'] as String), contains('Wrapper'));

        print('✅ httpClient auto-refresh flow succeeded');
      });

      test('when refresh fails httpClient throws AuthReLoginException', () async {
        print('\n🧪 httpClient: should throw AuthReLoginException when refresh fails');

        // Ensure a bad refresh token is stored for this test user
        await TokenVault.saveRefresh(clientUser2, 'this-refresh-token-is-invalid');
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
            user: clientUser2,
          );
          fail('Expected AuthReLoginException to be thrown');
        } on AuthReLoginException catch (e) {
          print('Caught expected AuthReLoginException: $e');
        }
      });
    });
}
