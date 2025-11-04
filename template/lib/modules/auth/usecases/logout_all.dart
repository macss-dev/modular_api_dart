import 'package:modular_api/modular_api.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/auth_repository.dart';

/// Input DTO for logout_all operation
/// Accepts a refresh token to identify the user
class LogoutAllInput implements Input {
  final String refreshToken;

  LogoutAllInput({required this.refreshToken});

  factory LogoutAllInput.fromJson(Map<String, dynamic> json) {
    return LogoutAllInput(refreshToken: json['refresh_token'] as String);
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
          'description': 'The refresh token to identify the user',
        },
      },
      'required': ['refresh_token'],
    };
  }
}

/// Output DTO for logout_all operation
/// Returns the count of revoked tokens
class LogoutAllOutput implements Output {
  final String message;
  final bool success;
  final int revokedCount;

  LogoutAllOutput({
    required this.message,
    required this.success,
    required this.revokedCount,
  });

  factory LogoutAllOutput.fromJson(Map<String, dynamic> json) {
    return LogoutAllOutput(
      message: json['message'] as String,
      success: json['success'] as bool,
      revokedCount: json['revoked_count'] as int,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'success': success,
      'revoked_count': revokedCount,
    };
  }

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'message': {'type': 'string', 'description': 'Success message'},
        'success': {
          'type': 'boolean',
          'description': 'Whether the logout_all was successful',
        },
        'revoked_count': {
          'type': 'integer',
          'description': 'Number of tokens revoked',
        },
      },
      'required': ['message', 'success', 'revoked_count'],
    };
  }
}

/// UseCase for logging out all sessions by revoking all user refresh tokens
class LogoutAllUseCase implements UseCase<LogoutAllInput, LogoutAllOutput> {
  @override
  final LogoutAllInput input;

  @override
  late LogoutAllOutput output;

  LogoutAllUseCase({required this.input}) {
    output = LogoutAllOutput(message: '', success: false, revokedCount: 0);
  }

  factory LogoutAllUseCase.factory(Map<String, dynamic> json) {
    return LogoutAllUseCase(input: LogoutAllInput.fromJson(json));
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

      // Extract user ID
      final userId = int.parse(jwt['sub'] as String);

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
        throw ArgumentError('Refresh token not found');
      }

      final tokenRecord = tokenRecords.first;
      final isRevoked = tokenRecord['revoked'] as bool;

      // Check if already revoked
      if (isRevoked) {
        throw ArgumentError('Refresh token has been revoked');
      }

      // Count active tokens before revoking
      final countResult = await db.query(
        '''
        SELECT COUNT(*) as count
        FROM auth.refresh_token
        WHERE id_user = @userId
          AND revoked = false
        ''',
        {'userId': userId},
      );

      final activeCount = countResult.first['count'] as int;

      if (activeCount == 0) {
        output = LogoutAllOutput(
          message: 'No active tokens to revoke',
          success: false,
          revokedCount: 0,
        );
        return;
      }

      // Revoke all user tokens
      await repo.revokeAllUserTokens(userId);

      output = LogoutAllOutput(
        message: 'Successfully logged out from all sessions',
        success: true,
        revokedCount: activeCount,
      );
    } catch (e) {
      if (e is ArgumentError) {
        rethrow;
      }
      throw Exception('Logout all failed: ${e.toString()}');
    } finally {
      await db.close();
    }
  }
}
