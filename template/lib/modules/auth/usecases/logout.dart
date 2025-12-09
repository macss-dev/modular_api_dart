import 'package:modular_api/modular_api.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/auth_repository.dart';

/// Input DTO for logout operation
/// Accepts a refresh token to identify and revoke
class LogoutInput implements Input {
  final String refreshToken;

  LogoutInput({required this.refreshToken});

  factory LogoutInput.fromJson(Map<String, dynamic> json) {
    return LogoutInput(refreshToken: json['refresh_token'] as String);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'refresh_token': refreshToken};
  }

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'refresh_token': {
          'type': 'string',
          'description': 'The refresh token to revoke',
        },
      },
      'required': ['refresh_token'],
    };
  }
}

/// Output DTO for logout operation
/// Returns a success message
class LogoutOutput extends Output {
  final String message;
  final bool success;

  LogoutOutput({required this.message, required this.success});

  factory LogoutOutput.fromJson(Map<String, dynamic> json) {
    return LogoutOutput(
      message: json['message'] as String,
      success: json['success'] as bool,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'message': message, 'success': success};
  }

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'message': {'type': 'string', 'description': 'Success message'},
        'success': {
          'type': 'boolean',
          'description': 'Whether the logout was successful',
        },
      },
      'required': ['message', 'success'],
    };
  }
}

/// UseCase for logging out a user by revoking their refresh token
class LogoutUseCase implements UseCase<LogoutInput, LogoutOutput> {
  @override
  final LogoutInput input;

  @override
  late LogoutOutput output;

  LogoutUseCase({required this.input}) {
    output = LogoutOutput(message: '', success: false);
  }

  factory LogoutUseCase.factory(Map<String, dynamic> json) {
    return LogoutUseCase(input: LogoutInput.fromJson(json));
  }

  @override
  Map<String, dynamic> toJson() => output.toJson();

  @override
  String? validate() {
    if (input.refreshToken.trim().isEmpty) {
      return 'Refresh token cannot be empty';
    }
    return null;
  }

  @override
  Future<void> execute() async {
    // Create database connection
    final db = PostgresClient();
    await db.connect();

    try {
      final repo = AuthRepository(db);

      // Verify the JWT and extract claims
      Map<String, dynamic> jwt;
      try {
        jwt = JwtHelper.verifyToken(input.refreshToken);
      } catch (e) {
        throw ArgumentError('Invalid refresh token: ${e.toString()}');
      }

      // Verify it's a refresh token
      final tokenType = jwt['type'] as String?;
      if (tokenType != 'refresh') {
        throw ArgumentError('Invalid token type. Expected refresh token');
      }

      // Extract token ID
      final tokenId = int.parse(jwt['jti'] as String);

      // Hash the token
      final tokenHash = TokenHasher.hash(input.refreshToken);

      // Verify the token exists (including revoked tokens)
      final tokenRecords = await db.query(
        '''
        SELECT id, id_user, revoked
        FROM auth.refresh_token
        WHERE token_hash = @tokenHash
        ''',
        {'tokenHash': tokenHash},
      );

      if (tokenRecords.isEmpty) {
        output = LogoutOutput(
          message: 'Refresh token not found',
          success: false,
        );
        return;
      }

      final tokenRecord = tokenRecords.first;
      final storedTokenId = tokenRecord['id'] as int;
      final isRevoked = tokenRecord['revoked'] as bool;

      // Verify token ID matches
      if (storedTokenId != tokenId) {
        throw ArgumentError('Invalid refresh token');
      }

      // Check if already revoked
      if (isRevoked) {
        output = LogoutOutput(message: 'Token already revoked', success: false);
        return;
      }

      // Revoke the token
      await repo.revokeRefreshToken(tokenId);

      output = LogoutOutput(message: 'Successfully logged out', success: true);
    } catch (e) {
      if (e is ArgumentError) {
        rethrow;
      }
      throw Exception('Logout failed: ${e.toString()}');
    } finally {
      await db.close();
    }
  }
}
