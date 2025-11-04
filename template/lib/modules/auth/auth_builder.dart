import 'package:modular_api/modular_api.dart';
import 'package:example/modules/auth/usecases/login.dart';
import 'package:example/modules/auth/usecases/refresh.dart';
import 'package:example/modules/auth/usecases/logout.dart';
import 'package:example/modules/auth/usecases/logout_all.dart';

void authBuilder(ModuleBuilder m) {
  m.usecase('login', LoginUseCase.factory);
  m.usecase('refresh', RefreshUseCase.factory);
  m.usecase('logout', LogoutUseCase.factory);
  m.usecase('logout_all', LogoutAllUseCase.factory);
}
