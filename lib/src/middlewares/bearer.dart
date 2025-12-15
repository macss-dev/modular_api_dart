/// Bearer token authentication middleware
///
/// Validates OAuth2 Bearer tokens using JWT and enforces scope requirements.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:modular_api/src/auth/oauth_service.dart';

/// Creates a Bearer token authentication middleware
///
/// Validates the Authorization header with Bearer token format.
/// Requires a valid JWT token signed with the configured secret.
///
/// Optionally enforces required scopes on protected routes.
///
/// Example:
/// ```dart
/// final oauthService = OAuthService(
///   jwtSecret: Env.getString('JWT_SECRET'),
///   issuer: 'api.example.com',
///   audience: 'api.example.com',
/// );
///
/// // Protect all routes
/// final api = ModularApi(basePath: '/api')
///   .use(bearer(oauthService));
///
/// // Or protect specific routes with scopes
/// api.module('webhook', (m) {
///   m.usecase('receive', ReceiveUseCase.fromJson,
///     requiredScopes: ['webhook:write']);
/// });
/// ```
Middleware bearer(OAuthService oauthService) {
  return (Handler innerHandler) {
    return (Request request) async {
      // Check if route requires authentication
      final requiresAuth = request.context['requiresAuth'] as bool? ?? false;
      if (!requiresAuth) {
        return innerHandler(request);
      }

      // Get Authorization header
      final authHeader = request.headers['authorization'];
      if (authHeader == null || authHeader.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'unauthorized',
            'error_description': 'Missing Authorization header',
          }),
          headers: {
            'Content-Type': 'application/json',
            'WWW-Authenticate': 'Bearer realm="api"',
          },
        );
      }

      // Validate Bearer format
      if (!authHeader.startsWith('Bearer ')) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'unauthorized',
            'error_description':
                'Invalid Authorization header format. Expected: Bearer <token>',
          }),
          headers: {
            'Content-Type': 'application/json',
            'WWW-Authenticate': 'Bearer realm="api"',
          },
        );
      }

      // Extract token
      final token = authHeader.substring(7).trim();
      if (token.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'unauthorized',
            'error_description': 'Token is empty',
          }),
          headers: {
            'Content-Type': 'application/json',
            'WWW-Authenticate': 'Bearer realm="api"',
          },
        );
      }

      // Get required scopes from context
      final requiredScopes =
          request.context['requiredScopes'] as List<String>? ?? [];

      // Validate token with scopes
      final accessToken = requiredScopes.isEmpty
          ? oauthService.validateToken(token)
          : oauthService.validateTokenWithScopes(token, requiredScopes);

      if (accessToken == null) {
        // Determine error reason
        String errorDescription = 'Invalid or expired token';
        final basicToken = oauthService.validateToken(token);
        if (basicToken != null && requiredScopes.isNotEmpty) {
          errorDescription =
              'Insufficient scopes. Required: ${requiredScopes.join(", ")}';
        }

        return Response(
          401,
          body: jsonEncode({
            'error': 'unauthorized',
            'error_description': errorDescription,
          }),
          headers: {
            'Content-Type': 'application/json',
            'WWW-Authenticate': 'Bearer realm="api"',
          },
        );
      }

      // Add access token to request context
      final updatedRequest = request.change(
        context: {
          ...request.context,
          'accessToken': accessToken,
          'clientId': accessToken.clientId,
          'scopes': accessToken.scopes,
        },
      );

      return innerHandler(updatedRequest);
    };
  };
}

/// Creates a middleware that marks routes as requiring authentication
///
/// Use this to mark specific routes that need Bearer token validation.
///
/// Example:
/// ```dart
/// final protectedHandler = Pipeline()
///   .addMiddleware(requireAuth())
///   .addMiddleware(bearer(oauthService))
///   .addHandler(myHandler);
/// ```
Middleware requireAuth([List<String> requiredScopes = const []]) {
  return (Handler innerHandler) {
    return (Request request) {
      final updatedRequest = request.change(
        context: {
          ...request.context,
          'requiresAuth': true,
          'requiredScopes': requiredScopes,
        },
      );
      return innerHandler(updatedRequest);
    };
  };
}
