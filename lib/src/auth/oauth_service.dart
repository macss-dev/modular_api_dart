/// OAuth2 service for managing clients and tokens
///
/// This service handles:
/// - Client authentication
/// - Token generation (JWT)
/// - Token validation
/// - Scope verification
library;

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:modular_api/src/auth/oauth_types.dart';

/// OAuth2 service for Client Credentials grant
///
/// Manages client authentication, token generation, and validation.
/// Uses HS256 (HMAC-SHA256) for JWT signing.
///
/// Example:
/// ```dart
/// final service = OAuthService(
///   jwtSecret: Env.getString('JWT_SECRET'),
///   issuer: 'api.example.com',
///   audience: 'api.example.com',
///   tokenTtlSeconds: 86400, // 24 hours
/// );
///
/// service.registerClient(OAuthClient(
///   clientId: 'finexo',
///   clientSecret: hashPassword('secret123'),
///   allowedScopes: ['webhook:write'],
/// ));
///
/// final response = service.authenticate(request);
/// ```
class OAuthService {
  /// JWT signing secret
  final String jwtSecret;

  /// Token issuer (iss claim)
  final String issuer;

  /// Token audience (aud claim)
  final String audience;

  /// Token TTL in seconds (default: 86400 = 24 hours)
  final int tokenTtlSeconds;

  /// Registered clients (in-memory)
  final Map<String, OAuthClient> _clients = {};

  OAuthService({
    required this.jwtSecret,
    required this.issuer,
    required this.audience,
    this.tokenTtlSeconds = 86400,
  });

  /// Registers a new OAuth client
  ///
  /// The client secret should be hashed before registration:
  /// ```dart
  /// final hashedSecret = hashPassword('plain_secret');
  /// service.registerClient(OAuthClient(
  ///   clientId: 'client1',
  ///   clientSecret: hashedSecret,
  ///   allowedScopes: ['read', 'write'],
  /// ));
  /// ```
  void registerClient(OAuthClient client) {
    _clients[client.clientId] = client;
  }

  /// Registers multiple clients at once
  void registerClients(List<OAuthClient> clients) {
    for (final client in clients) {
      registerClient(client);
    }
  }

  /// Gets a registered client by ID
  OAuthClient? getClient(String clientId) {
    return _clients[clientId];
  }

  /// Authenticates a token request and generates JWT
  ///
  /// Validates:
  /// - Grant type is "client_credentials"
  /// - Client exists and is active
  /// - Client secret matches
  /// - Requested scopes are allowed
  ///
  /// Returns [TokenResponse] on success, [TokenErrorResponse] on failure.
  dynamic authenticate(TokenRequest request) {
    // Validate grant type
    if (request.grantType != 'client_credentials') {
      return TokenErrorResponse(
        error: 'unsupported_grant_type',
        errorDescription: 'Grant type must be "client_credentials"',
      );
    }

    // Find client
    final client = _clients[request.clientId];
    if (client == null) {
      return TokenErrorResponse(
        error: 'invalid_client',
        errorDescription: 'Client not found',
      );
    }

    // Check if client is active
    if (!client.isActive) {
      return TokenErrorResponse(
        error: 'invalid_client',
        errorDescription: 'Client is disabled',
      );
    }

    // Validate client secret
    // Note: In production, use hashPassword() to hash the secret before comparison
    if (client.clientSecret != request.clientSecret) {
      return TokenErrorResponse(
        error: 'invalid_client',
        errorDescription: 'Invalid client credentials',
      );
    }

    // Validate requested scopes
    final requestedScopes = request.requestedScopes;
    for (final scope in requestedScopes) {
      if (!client.allowedScopes.contains(scope)) {
        return TokenErrorResponse(
          error: 'invalid_scope',
          errorDescription: 'Scope "$scope" is not allowed for this client',
        );
      }
    }

    // Use all allowed scopes if none requested
    final grantedScopes =
        requestedScopes.isEmpty ? client.allowedScopes : requestedScopes;

    // Generate JWT
    final now = DateTime.now();
    final iat = now.millisecondsSinceEpoch ~/ 1000;
    final exp = iat + tokenTtlSeconds;

    final payload = {
      'sub': client.clientId,
      'iss': issuer,
      'aud': audience,
      'iat': iat,
      'exp': exp,
      'scopes': grantedScopes,
      'client_id': client.clientId,
    };

    final jwt = JWT(payload);
    final token = jwt.sign(SecretKey(jwtSecret));

    return TokenResponse(
      accessToken: token,
      tokenType: 'Bearer',
      expiresIn: tokenTtlSeconds,
      scope: grantedScopes.join(' '),
    );
  }

  /// Validates a JWT access token
  ///
  /// Checks:
  /// - JWT signature is valid
  /// - Token has not expired
  /// - Issuer and audience match
  ///
  /// Returns [AccessToken] on success, null on failure.
  AccessToken? validateToken(String token) {
    try {
      // Verify JWT signature and decode
      final jwt = JWT.verify(token, SecretKey(jwtSecret));
      final payload = jwt.payload as Map<String, dynamic>;

      // Parse as AccessToken
      final accessToken = AccessToken.fromPayload(payload);

      // Check expiration
      if (accessToken.isExpired) {
        return null;
      }

      // Verify issuer
      if (accessToken.iss != issuer) {
        return null;
      }

      // Verify audience
      if (accessToken.aud != audience) {
        return null;
      }

      return accessToken;
    } on JWTExpiredException {
      return null;
    } on JWTException {
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Validates token and checks if it has all required scopes
  ///
  /// Returns [AccessToken] if valid and has scopes, null otherwise.
  AccessToken? validateTokenWithScopes(
    String token,
    List<String> requiredScopes,
  ) {
    final accessToken = validateToken(token);
    if (accessToken == null) {
      return null;
    }

    if (!accessToken.hasAllScopes(requiredScopes)) {
      return null;
    }

    return accessToken;
  }

  /// Checks if a client exists and is active
  bool isClientActive(String clientId) {
    final client = _clients[clientId];
    return client != null && client.isActive;
  }

  /// Gets all registered client IDs
  List<String> getAllClientIds() {
    return _clients.keys.toList();
  }

  /// Removes a client
  void removeClient(String clientId) {
    _clients.remove(clientId);
  }

  /// Clears all registered clients
  void clearClients() {
    _clients.clear();
  }
}
