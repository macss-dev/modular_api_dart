import 'package:modular_api/modular_api.dart';
import 'package:example/modules/module2/usecases/usecase_1.dart';
import 'package:example/modules/module2/usecases/usecase_2.dart';
/* 
  Endpoints (servidor)
    POST /v0/auth/login
      In: { username, password }
      Out: { access_token, token_type: "Bearer", expires_in, refresh_token }
    POST /v0/auth/refresh
      In: { refresh_token }
      Out: { access_token, token_type: "Bearer", expires_in, refresh_token? }
      Si rotas, devuelves un refresh nuevo y revocas el anterior.
    POST /v0/auth/logout
      In: { refresh_token } (o implícito por sesión)
      Acción: revoca ese refresh.
    POST /v0/auth/logout_all (opcional)
      Revoca toda la familia de refresh del usuario (sign-out global).
 */
void authBuilder(ModuleBuilder m) {
  m.usecase('login', A.fromJson);
  m.usecase('refresh', B.fromJson);
  m.usecase('logout', B.fromJson);
  m.usecase('logout_all', B.fromJson);
}
