import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

/// End-to-end test to verify the server runs correctly.
///
/// This test starts the server with environment variables loaded from `.env`.
void main() {
  late Process serverProcess;
  const serverUrl = 'http://localhost:3456';
  const healthEndpoint = '$serverUrl/health';

  /// Reads the `.env` file and returns a map of environment variables.
  Map<String, String> loadEnvVariables() {
    final envFile = File('.env');
    if (!envFile.existsSync()) {
      throw Exception('.env file not found');
    }

    final envVars = <String, String>{};
    final lines = envFile.readAsLinesSync();

    for (var line in lines) {
      line = line.trim();
      // Ignore empty lines and comments
      if (line.isEmpty || line.startsWith('#')) continue;

      // Parse KEY=VALUE
      final separatorIndex = line.indexOf('=');
      if (separatorIndex == -1) continue;

      final key = line.substring(0, separatorIndex).trim();
      var value = line.substring(separatorIndex + 1).trim();

      // Remove surrounding quotes if present
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
    print('\n🚀 Starting server with environment variables...');

    // Load environment variables from .env
    final envVars = loadEnvVariables();
    print('📋 Loaded variables: ${envVars.keys.join(', ')}');

    // Start the server with the environment variables
    serverProcess = await Process.start(
      'dart',
      ['run', 'bin/example.dart'],
      environment: envVars,
      workingDirectory: Directory.current.path,
    );

    // Capture server logs
    serverProcess.stdout.transform(utf8.decoder).listen((data) {
      print('📤 SERVER: $data');
    });

    serverProcess.stderr.transform(utf8.decoder).listen((data) {
      print('⚠️  SERVER ERROR: $data');
    });

    // Wait for the server to be ready
    print('⏳ Waiting for server to be ready...');
    var attempts = 0;
    const maxAttempts = 30; // ~15 seconds max
    var serverReady = false;

    while (attempts < maxAttempts && !serverReady) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final response = await http
            .get(Uri.parse(healthEndpoint))
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          serverReady = true;
          print('✅ Server ready at $serverUrl');
        }
      } catch (e) {
        attempts++;
        if (attempts % 4 == 0) {
          print('   Attempt ${attempts ~/ 2}/${maxAttempts ~/ 2}...');
        }
      }
    }

    if (!serverReady) {
      serverProcess.kill();
      throw Exception(
        '❌ Server did not respond after $maxAttempts attempts',
      );
    }
  });

  tearDownAll(() async {
    print('\n🛑 Stopping server...');
    serverProcess.kill();
    await serverProcess.exitCode;
    print('✅ Server stopped');
  });

  group('E2E - Health Check', () {
    test('GET /health should return 200 OK', () async {
      print('\n🧪 Test: Checking /health endpoint');

      final response = await http.get(Uri.parse(healthEndpoint));

      print('   Status: ${response.statusCode}');
      print('   Body: ${response.body}');

      expect(
        response.statusCode,
        equals(200),
        reason: 'The /health endpoint must return 200',
      );

      // Verify the response contains "ok"
      expect(
        response.body.trim(),
        equals('ok'),
        reason: 'The body should contain "ok"',
      );

      print('✅ Health check successful');
    });

    test('Server should be listening on the expected port', () async {
      print('\n🧪 Test: Verifying server port');

      // Request a non-existent route to ensure the server responds
      final response = await http.get(
        Uri.parse('$serverUrl/non-existent-route'),
      );

      print('   Status: ${response.statusCode}');

      // Should respond (401, 404, etc.), confirming the server is listening
      expect(
        response.statusCode,
        isIn([401, 404, 405, 500]),
        reason: 'Server should respond even for non-existent routes',
      );

      print('✅ Server is listening correctly');
    });

    test('Server should have CORS configured', () async {
      print('\n🧪 Test: Checking CORS headers');

      final response = await http.get(Uri.parse(healthEndpoint));

      print('   Headers: ${response.headers}');

      // Check for CORS headers (if configured)
      final hasCors = response.headers.containsKey(
        'access-control-allow-origin',
      );
      print('   CORS enabled: $hasCors');

      if (hasCors) {
        print(
          '   CORS Origin: ${response.headers['access-control-allow-origin']}',
        );
        print('✅ CORS configured');
      } else {
        print('⚠️  CORS not detected (may be optional)');
      }
    });
  });
}
