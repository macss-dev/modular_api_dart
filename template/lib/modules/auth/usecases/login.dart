import 'package:modular_api/modular_api.dart';
import 'package:example/db/postgres_client.dart';
import 'package:example/modules/auth/auth_repository.dart';

/// Input for login operation.
class LoginInput implements Input {
  final String username;
  final String password;

  LoginInput({required this.username, required this.password});

  factory LoginInput.fromJson(Map<String, dynamic> json) {
    return LoginInput(
      username: json['username'] as String,
      password: json['password'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {'username': username, 'password': password};

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'username': {
          'type': 'string',
          'description': 'Username for authentication',
          'minLength': 3,
          'maxLength': 16,
        },
        'password': {
          'type': 'string',
          'description': 'User password',
          'minLength': 6,
        },
      },
      'required': ['username', 'password'],
    };
  }
}

/// Output for successful login.
class LoginOutput extends Output {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String refreshToken;

  LoginOutput({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshToken,
  });

  factory LoginOutput.fromJson(Map<String, dynamic> json) {
    return LoginOutput(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      expiresIn: json['expires_in'] as int,
      refreshToken: json['refresh_token'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'token_type': tokenType,
    'expires_in': expiresIn,
    'refresh_token': refreshToken,
  };

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'access_token': {
          'type': 'string',
          'description': 'JWT access token for API requests',
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
          'description': 'JWT refresh token for obtaining new access tokens',
        },
      },
      'required': ['access_token', 'token_type', 'expires_in', 'refresh_token'],
    };
  }
}

/// Login use case.
///
/// Authenticates a user with username and password.
/// Returns access and refresh tokens on success.
class LoginUseCase implements UseCase<LoginInput, LoginOutput> {
  @override
  final LoginInput input;

  @override
  late LoginOutput output;

  LoginUseCase({required this.input}) {
    output = LoginOutput(
      accessToken: '',
      tokenType: 'Bearer',
      expiresIn: 0,
      refreshToken: '',
    );
  }

  factory LoginUseCase.factory(Map<String, dynamic> json) {
    return LoginUseCase(input: LoginInput.fromJson(json));
  }

  @override
  String? validate() {
    if (input.username.isEmpty || input.password.isEmpty) {
      return 'Username and password are required';
    }

    if (input.username.length < 3 || input.username.length > 16) {
      return 'Username must be between 3 and 16 characters';
    }

    if (input.password.length < 6) {
      return 'Password must be at least 6 characters';
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

      // Authenticate user
      final user = await repo.authenticate(input.username, input.password);

      if (user == null) {
        throw ArgumentError('Invalid credentials');
      }

      final userId = user['id'] as int;
      final username = user['username'] as String;

      // Generate access token
      final accessToken = JwtHelper.generateAccessToken(
        userId: userId,
        username: username,
      );

      // Generate JWT refresh token with the correct token ID
      // First, save a placeholder record to get the ID
      final placeholderHash = TokenHasher.hash(
        'placeholder-${DateTime.now().millisecondsSinceEpoch}',
      );

      final tokenId = await repo.saveRefreshToken(
        userId: userId,
        tokenHash: placeholderHash,
        expiresAt: JwtHelper.calculateRefreshTokenExpiration(),
      );

      // Now generate the actual refresh token with correct token ID
      final refreshToken = JwtHelper.generateRefreshToken(
        userId: userId,
        tokenId: tokenId,
      );

      // Hash the actual refresh token and update the record
      final refreshTokenHash = TokenHasher.hash(refreshToken);
      await db.execute(
        '''
        UPDATE auth.refresh_token
        SET token_hash = @tokenHash
        WHERE id = @tokenId
        ''',
        {'tokenHash': refreshTokenHash, 'tokenId': tokenId},
      );

      output = LoginOutput(
        accessToken: accessToken,
        tokenType: 'Bearer',
        expiresIn: JwtHelper.accessTokenExpiresIn,
        refreshToken: refreshToken,
      );
    } finally {
      await db.close();
    }
  }

  @override
  Map<String, dynamic> toJson() => output.toJson();
}
