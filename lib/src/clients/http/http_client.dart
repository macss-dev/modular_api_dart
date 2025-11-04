import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/http.dart';

import 'auth_exceptions.dart';
import 'token.dart';
import 'token_vault.dart';

/// Attempts to refresh the access token using the stored refresh token.
///
/// Returns true if refresh was successful and Session.accessToken was updated.
/// Returns false if refresh token is not available or refresh failed.
///
/// This function:
/// 1. Reads the refresh token from secure storage
/// 2. Calls POST /api/auth/refresh with the refresh token
/// 3. Updates Session.accessToken and Session.accessExp on success
/// 4. Optionally saves a new refresh token if token rotation is enabled
Future<bool> _tryRefresh({
  required String baseUrl,
  required String refreshEndpoint,
  required String user,
}) async {
  final rt = await TokenVault.readRefresh(user);
  if (rt == null) return false;

  final url = Uri.parse('$baseUrl/$refreshEndpoint');
  try {
    final r = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': rt}),
        )
        .timeout(const Duration(seconds: 30));

    if (r.statusCode == 200) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      final access = m['access_token'] as String?;
      final expiresIn = (m['expires_in'] as num?)?.toInt();
      final newRt = m['refresh_token'] as String?;

      if (access == null) return false;

      // Update in-memory session
      Token.accessToken = access;
      if (expiresIn != null) {
        Token.accessExp = DateTime.now().add(Duration(seconds: expiresIn));
      }

      // Update refresh token if rotation is enabled
      if (newRt != null) {
        await TokenVault.saveRefresh(user, newRt);
      }

      return true;
    }
    return false;
  } catch (e) {
    stderr.writeln('Token refresh error: $e');
    return false;
  }
}

/// HTTP client with automatic authentication support.
///
/// Features:
/// - Automatic Bearer token attachment when [auth] is true
/// - Captures access_token and refresh_token from login responses
/// - Auto-retry with token refresh on 401 responses
/// - Throws [AuthReLoginException] when refresh fails (signals re-login needed)
///
/// Usage:
/// ```dart
/// // Login endpoint (captures tokens automatically)
/// final loginData = await httpClient(
///   method: 'POST',
///   baseUrl: 'https://api.example.com',
///   endpoint: 'v0/auth/login',
///   body: {'username': 'user', 'password': 'pass'},
///   auth: true,
///   user: 'user123',
/// );
///
/// // Protected endpoint (auto Bearer token + retry on 401)
/// try {
///   final data = await httpClient(
///     method: 'GET',
///     baseUrl: 'https://api.example.com',
///     endpoint: 'v0/users/me',
///     auth: true,
///     user: 'user123',
///   );
/// } on AuthReLoginException {
///   // Navigate to login screen
/// }
/// ```
Future<dynamic> httpClient({
  required String method,
  required String baseUrl,
  required String endpoint,
  Map<String, String>? headers,
  Map<String, dynamic>? body,
  String errorMessage = 'Error in HTTP request',
  bool auth = false,
  String? user,
}) async {
  try {
    final url = Uri.parse('$baseUrl/$endpoint');
    late Response response;
    final effectiveHeaders = <String, String>{
      'Content-Type': 'application/json',
      if (headers != null) ...headers,
    };

    // Attach Bearer token if auth=true and we have an access token in memory
    if (auth && Token.accessToken != null) {
      effectiveHeaders['Authorization'] = 'Bearer ${Token.accessToken}';
    }

    // Helper to execute the actual HTTP request
    Future<Response> doCall() {
      switch (method.toUpperCase()) {
        case 'GET':
          return get(url, headers: effectiveHeaders)
              .timeout(const Duration(seconds: 30));
        case 'POST':
          return post(url,
                  headers: effectiveHeaders, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 30));
        case 'PATCH':
          return patch(
            url,
            headers: effectiveHeaders,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(const Duration(seconds: 30));
        default:
          throw Exception('Unsupported HTTP method: $method');
      }
    }

    // Execute the request
    response = await doCall();

    // Special case: LOGIN endpoint - capture tokens automatically
    final bool isLogin = endpoint.contains('/auth/login');
    if (isLogin && auth && response.statusCode == 200) {
      final m = jsonDecode(response.body) as Map<String, dynamic>;
      final access = m['access_token'] as String?;
      final expiresIn = (m['expires_in'] as num?)?.toInt();
      final rt = m['refresh_token'] as String?;

      if (access != null) {
        Token.accessToken = access;
      }
      if (expiresIn != null) {
        Token.accessExp = DateTime.now().add(Duration(seconds: expiresIn));
      }
      if (rt != null && user != null) {
        await TokenVault.saveRefresh(user, rt);
      }
      return m; // Return the login response
    }

    // Handle 401 on protected endpoints: try refresh and retry once
    if (response.statusCode == 401 && auth) {
      if (user != null) {
        // Infer refresh endpoint: if endpoint is 'api/module/...' then use 'api/auth/refresh'
        // if endpoint is 'v1/resource/...' then use 'v1/auth/refresh', etc.
        String refreshEndpoint = 'auth/refresh';
        if (endpoint.contains('/')) {
          final parts = endpoint.split('/');
          if (parts.isNotEmpty && parts[0].isNotEmpty) {
            // Use the first segment as the API prefix
            refreshEndpoint = '${parts[0]}/auth/refresh';
          }
        }
        
        final refreshed = await _tryRefresh(
          baseUrl: baseUrl,
          refreshEndpoint: refreshEndpoint,
          user: user,
        );
        if (refreshed) {
          // Update Authorization header with new token and retry
          effectiveHeaders['Authorization'] = 'Bearer ${Token.accessToken}';
          response = await doCall();
        }
      }
    }

    // Success (2xx)
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isNotEmpty ? jsonDecode(response.body) : null;
    }

    // If still 401 after refresh attempt → signal re-login required
    if (response.statusCode == 401 && auth) {
      throw AuthReLoginException();
    }

    // Other errors: preserve original behavior
    throw Exception('$errorMessage: ${response.statusCode}');
  } catch (e) {
    // Re-throw AuthReLoginException without wrapping
    if (e is AuthReLoginException) rethrow;

    stderr.writeln('HTTP Client Error: $e');
    throw Exception('$errorMessage: [Connection error] - $e');
  }
}
