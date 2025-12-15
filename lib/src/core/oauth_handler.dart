/// OAuth2 token endpoint handler
///
/// Provides the POST /oauth/token endpoint for Client Credentials grant.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:modular_api/src/auth/oauth_service.dart';
import 'package:modular_api/src/auth/oauth_types.dart';

/// Creates a handler for POST /oauth/token
///
/// Implements OAuth2 Client Credentials grant (RFC 6749 Section 4.4).
///
/// Request format:
/// ```json
/// {
///   "grant_type": "client_credentials",
///   "client_id": "your_client_id",
///   "client_secret": "your_client_secret",
///   "scope": "read write"  // optional
/// }
/// ```
///
/// Success response (HTTP 200):
/// ```json
/// {
///   "access_token": "eyJhbGc...",
///   "token_type": "Bearer",
///   "expires_in": 86400,
///   "scope": "read write"
/// }
/// ```
///
/// Error response (HTTP 400/401):
/// ```json
/// {
///   "error": "invalid_client",
///   "error_description": "Client not found"
/// }
/// ```
Handler createOAuthTokenHandler(OAuthService oauthService) {
  return (Request request) async {
    // Only accept POST
    if (request.method != 'POST') {
      return Response(
        405,
        body: jsonEncode({
          'error': 'method_not_allowed',
          'error_description': 'Only POST method is allowed',
        }),
        headers: {
          'Content-Type': 'application/json',
          'Allow': 'POST',
        },
      );
    }

    // Parse request body
    late final TokenRequest tokenRequest;
    try {
      final body = await request.readAsString();
      if (body.isEmpty) {
        return _errorResponse(
          400,
          'invalid_request',
          'Request body is empty',
        );
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      tokenRequest = TokenRequest.fromJson(json);
    } catch (e) {
      return _errorResponse(
        400,
        'invalid_request',
        'Invalid JSON or missing required fields: $e',
      );
    }

    // Authenticate and generate token
    final result = oauthService.authenticate(tokenRequest);

    // Handle success
    if (result is TokenResponse) {
      return Response.ok(
        jsonEncode(result.toJson()),
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
          'Pragma': 'no-cache',
        },
      );
    }

    // Handle error
    if (result is TokenErrorResponse) {
      final statusCode = _getStatusCodeForError(result.error);
      return Response(
        statusCode,
        body: jsonEncode(result.toJson()),
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
          'Pragma': 'no-cache',
        },
      );
    }

    // Unexpected result type
    return _errorResponse(
      500,
      'server_error',
      'Unexpected authentication result',
    );
  };
}

/// Helper: Creates error response
Response _errorResponse(int statusCode, String error, String description) {
  return Response(
    statusCode,
    body: jsonEncode({
      'error': error,
      'error_description': description,
    }),
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'Pragma': 'no-cache',
    },
  );
}

/// Helper: Maps OAuth error codes to HTTP status codes
int _getStatusCodeForError(String error) {
  switch (error) {
    case 'invalid_request':
      return 400; // Bad Request
    case 'invalid_client':
      return 401; // Unauthorized
    case 'invalid_grant':
      return 400; // Bad Request
    case 'unauthorized_client':
      return 400; // Bad Request
    case 'unsupported_grant_type':
      return 400; // Bad Request
    case 'invalid_scope':
      return 400; // Bad Request
    default:
      return 400; // Default to Bad Request
  }
}
