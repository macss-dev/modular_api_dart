import 'package:modular_api/modular_api.dart';
import 'package:example/modules/module2/usecases/usecase_1.dart';
import 'package:example/modules/module2/usecases/usecase_2.dart';
/*
  Endpoints (server)
    POST /v0/auth/login
      Input: { username, password }
      Output: { access_token, token_type: "Bearer", expires_in, refresh_token }
    POST /v0/auth/refresh
      Input: { refresh_token }
      Output: { access_token, token_type: "Bearer", expires_in, refresh_token? }
      If refresh token rotation is enabled, return a new refresh token and revoke the previous one.
    POST /v0/auth/logout
      Input: { refresh_token } (or implicit via session)
      Action: revoke the provided refresh token.
    POST /v0/auth/logout_all (optional)
      Revoke all refresh tokens for the user (global sign-out).
*/
void authBuilder(ModuleBuilder m) {
  m.usecase('login', A.fromJson);
  m.usecase('refresh', B.fromJson);
  // m.usecase('logout', B.fromJson); 
  // m.usecase('logout_all', B.fromJson);
}
