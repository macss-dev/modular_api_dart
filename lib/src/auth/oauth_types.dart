/// OAuth2 types and data structures for modular_api
///
/// This file defines the core data structures used in OAuth2 authentication:
/// - Client credentials
/// - Token requests/responses
/// - Access tokens with metadata
library;

/// OAuth2 client credentials
///
/// Represents a registered client application with its credentials.
/// Used in Client Credentials grant flow.
class OAuthClient {
  /// Unique client identifier
  final String clientId;

  /// Client secret (hashed in production)
  final String clientSecret;

  /// Allowed scopes for this client
  final List<String> allowedScopes;

  /// Human-readable client name
  final String? name;

  /// Client description
  final String? description;

  /// Whether this client is active
  final bool isActive;

  const OAuthClient({
    required this.clientId,
    required this.clientSecret,
    required this.allowedScopes,
    this.name,
    this.description,
    this.isActive = true,
  });

  /// Creates client from JSON
  factory OAuthClient.fromJson(Map<String, dynamic> json) {
    return OAuthClient(
      clientId: json['clientId'] as String,
      clientSecret: json['clientSecret'] as String,
      allowedScopes: (json['allowedScopes'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      name: json['name'] as String?,
      description: json['description'] as String?,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  /// Converts client to JSON
  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      'clientSecret': clientSecret,
      'allowedScopes': allowedScopes,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      'isActive': isActive,
    };
  }
}

/// OAuth2 token request (Client Credentials grant)
///
/// Request payload for POST /oauth/token
class TokenRequest {
  /// Must be "client_credentials"
  final String grantType;

  /// Client identifier
  final String clientId;

  /// Client secret
  final String clientSecret;

  /// Space-separated list of requested scopes
  final String? scope;

  const TokenRequest({
    required this.grantType,
    required this.clientId,
    required this.clientSecret,
    this.scope,
  });

  /// Creates request from JSON
  factory TokenRequest.fromJson(Map<String, dynamic> json) {
    return TokenRequest(
      grantType: json['grant_type'] as String,
      clientId: json['client_id'] as String,
      clientSecret: json['client_secret'] as String,
      scope: json['scope'] as String?,
    );
  }

  /// Converts request to JSON
  Map<String, dynamic> toJson() {
    return {
      'grant_type': grantType,
      'client_id': clientId,
      'client_secret': clientSecret,
      if (scope != null) 'scope': scope,
    };
  }

  /// Gets requested scopes as list
  List<String> get requestedScopes {
    if (scope == null || scope!.isEmpty) return [];
    return scope!.split(' ').where((s) => s.isNotEmpty).toList();
  }
}

/// OAuth2 token response
///
/// Successful response from POST /oauth/token
class TokenResponse {
  /// JWT access token
  final String accessToken;

  /// Token type (always "Bearer")
  final String tokenType;

  /// Expiration time in seconds
  final int expiresIn;

  /// Granted scopes (space-separated)
  final String? scope;

  const TokenResponse({
    required this.accessToken,
    this.tokenType = 'Bearer',
    required this.expiresIn,
    this.scope,
  });

  /// Creates response from JSON
  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: json['expires_in'] as int,
      scope: json['scope'] as String?,
    );
  }

  /// Converts response to JSON
  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'token_type': tokenType,
      'expires_in': expiresIn,
      if (scope != null) 'scope': scope,
    };
  }
}

/// OAuth2 error response
///
/// Error response from POST /oauth/token following RFC 6749
class TokenErrorResponse {
  /// Error code (invalid_request, invalid_client, invalid_grant, etc.)
  final String error;

  /// Human-readable error description
  final String? errorDescription;

  /// URI with error information
  final String? errorUri;

  const TokenErrorResponse({
    required this.error,
    this.errorDescription,
    this.errorUri,
  });

  /// Creates error from JSON
  factory TokenErrorResponse.fromJson(Map<String, dynamic> json) {
    return TokenErrorResponse(
      error: json['error'] as String,
      errorDescription: json['error_description'] as String?,
      errorUri: json['error_uri'] as String?,
    );
  }

  /// Converts error to JSON
  Map<String, dynamic> toJson() {
    return {
      'error': error,
      if (errorDescription != null) 'error_description': errorDescription,
      if (errorUri != null) 'error_uri': errorUri,
    };
  }
}

/// Decoded JWT access token payload
///
/// Contains claims from a validated JWT token
class AccessToken {
  /// Token subject (typically client_id)
  final String sub;

  /// Token issuer
  final String iss;

  /// Token audience
  final String aud;

  /// Issued at timestamp (seconds since epoch)
  final int iat;

  /// Expiration timestamp (seconds since epoch)
  final int exp;

  /// Granted scopes
  final List<String> scopes;

  /// Client ID
  final String clientId;

  const AccessToken({
    required this.sub,
    required this.iss,
    required this.aud,
    required this.iat,
    required this.exp,
    required this.scopes,
    required this.clientId,
  });

  /// Creates token from JWT payload
  factory AccessToken.fromPayload(Map<String, dynamic> payload) {
    return AccessToken(
      sub: payload['sub'] as String,
      iss: payload['iss'] as String,
      aud: payload['aud'] as String,
      iat: payload['iat'] as int,
      exp: payload['exp'] as int,
      scopes:
          (payload['scopes'] as List<dynamic>).map((e) => e as String).toList(),
      clientId: payload['client_id'] as String,
    );
  }

  /// Converts token to payload map
  Map<String, dynamic> toPayload() {
    return {
      'sub': sub,
      'iss': iss,
      'aud': aud,
      'iat': iat,
      'exp': exp,
      'scopes': scopes,
      'client_id': clientId,
    };
  }

  /// Checks if token has expired
  bool get isExpired {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  /// Checks if token has specific scope
  bool hasScope(String scope) {
    return scopes.contains(scope);
  }

  /// Checks if token has all required scopes
  bool hasAllScopes(List<String> requiredScopes) {
    return requiredScopes.every((scope) => scopes.contains(scope));
  }

  /// Checks if token has any of the required scopes
  bool hasAnyScope(List<String> requiredScopes) {
    return requiredScopes.any((scope) => scopes.contains(scope));
  }
}
