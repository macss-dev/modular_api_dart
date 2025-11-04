import 'package:modular_api/modular_api.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/auth_repository.dart';

/// Input for refresh token operation.
class RefreshInput implements Input {
  final String refreshToken;

  RefreshInput({required this.refreshToken});

  factory RefreshInput.fromJson(Map<String, dynamic> json) {
    return RefreshInput(refreshToken: json['refresh_token'] as String);
  }

  @override
  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'refresh_token': {
          'type': 'string',
          'description': 'JWT refresh token to exchange for a new access token',
        },
      },
      'required': ['refresh_token'],
    };
  }
}

/// Output for refresh token operation.
class RefreshOutput implements Output {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String? refreshToken; // Optional: returned if rotation is enabled

  RefreshOutput({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.refreshToken,
  });

  factory RefreshOutput.fromJson(Map<String, dynamic> json) {
    return RefreshOutput(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      expiresIn: json['expires_in'] as int,
      refreshToken: json['refresh_token'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final result = {
      'access_token': accessToken,
      'token_type': tokenType,
      'expires_in': expiresIn,
    };
    if (refreshToken != null) {
      result['refresh_token'] = refreshToken!;
    }
    return result;
  }

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'access_token': {
          'type': 'string',
          'description': 'New JWT access token',
        },
        'token_type': {
          'type': 'string',
          'description': 'Token type (always "Bearer")',
          'enum': ['Bearer'],
        },
        'expires_in': {
          'type': 'integer',
          'description': 'Access token expiration time in seconds',
        },
        'refresh_token': {
          'type': 'string',
          'description':
              'New refresh token (optional, returned if rotation is enabled)',
        },
      },
      'required': ['access_token', 'token_type', 'expires_in'],
    };
  }
}

/// Refresh token use case.
///
/// Validates a refresh token and issues a new access token.
/// Optionally implements token rotation for enhanced security.
class RefreshUseCase implements UseCase<RefreshInput, RefreshOutput> {
  @override
  final RefreshInput input;

  @override
  late RefreshOutput output;

  /// Enable refresh token rotation (recommended for production).
  /// When enabled, a new refresh token is issued and the old one is revoked.
  final bool enableRotation;

  RefreshUseCase({required this.input, this.enableRotation = true}) {
    output = RefreshOutput(accessToken: '', tokenType: 'Bearer', expiresIn: 0);
  }

  factory RefreshUseCase.factory(Map<String, dynamic> json) {
    return RefreshUseCase(input: RefreshInput.fromJson(json));
  }

  @override
  String? validate() {
    if (input.refreshToken.isEmpty) {
      return 'Refresh token is required';
    }

    return null;
  }

  @override
  Future<void> execute() async {
    // Verify JWT token
    Map<String, dynamic> payload;
    try {
      payload = JwtHelper.verifyToken(input.refreshToken);
    } on JwtException catch (e) {
      throw ArgumentError('Invalid refresh token: ${e.message}');
    }

    // Extract user ID and token ID from JWT
    final userIdStr = payload['sub'] as String?;
    final tokenIdStr = payload['jti'] as String?;

    if (userIdStr == null || tokenIdStr == null) {
      throw ArgumentError('Invalid token payload');
    }

    final userId = int.parse(userIdStr);
    final tokenId = int.parse(tokenIdStr);

    // Connect to database
    final db = PostgresClient();
    await db.connect();

    try {
      final repo = AuthRepository(db);

      // Hash the token for database lookup
      final tokenHash = TokenHasher.hash(input.refreshToken);

      // Verify token exists in database and is not revoked
      final tokenRecord = await repo.getRefreshToken(tokenHash);

      if (tokenRecord == null) {
        throw ArgumentError('Refresh token not found or has been revoked');
      }

      // Verify token belongs to the correct user
      final recordUserId = tokenRecord['id_user'] as int;
      if (recordUserId != userId) {
        throw ArgumentError('Token user mismatch');
      }

      // Check expiration
      final expiresAt = tokenRecord['expires_at'] as DateTime;
      if (DateTime.now().isAfter(expiresAt)) {
        throw ArgumentError('Refresh token has expired');
      }

      // Get user information
      final user = await repo.getUserById(userId);
      if (user == null) {
        throw ArgumentError('User not found');
      }

      final username = user['username'] as String;

      // Generate new access token
      final accessToken = JwtHelper.generateAccessToken(
        userId: userId,
        username: username,
      );

      String? newRefreshToken;

      if (enableRotation) {
        // Revoke the old refresh token
        await repo.revokeRefreshToken(tokenId);

        // Save placeholder record to get new token ID
        final placeholderHash = TokenHasher.hash(
          'placeholder-${DateTime.now().millisecondsSinceEpoch}',
        );

        final newTokenId = await repo.saveRefreshToken(
          userId: userId,
          tokenHash: placeholderHash,
          expiresAt: JwtHelper.calculateRefreshTokenExpiration(),
          previousId: tokenId, // Link to previous token
        );

        // Generate the actual refresh token with correct ID
        newRefreshToken = JwtHelper.generateRefreshToken(
          userId: userId,
          tokenId: newTokenId,
        );

        // Hash the actual token and update the record
        final newTokenHash = TokenHasher.hash(newRefreshToken);
        await db.execute(
          '''
          UPDATE auth.refresh_token
          SET token_hash = @tokenHash
          WHERE id = @tokenId
          ''',
          {'tokenHash': newTokenHash, 'tokenId': newTokenId},
        );
      }

      output = RefreshOutput(
        accessToken: accessToken,
        tokenType: 'Bearer',
        expiresIn: JwtHelper.accessTokenExpiresIn,
        refreshToken: newRefreshToken,
      );
    } finally {
      await db.close();
    }
  }

  @override
  Map<String, dynamic> toJson() => output.toJson();
}
