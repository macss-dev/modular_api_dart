import 'package:modular_api/modular_api.dart';

/// Factory to create an ODBC client targeting SQL Server.
/// Reads environment variables:
/// - MSSQL_DSN
/// - MSSQL_USER
/// - MSSQL_PASSWORD
DbClient createSqlServerClient({bool autoConnect = false}) {
  final dsn = Env.getString('MSSQL_DSN');
  final user = Env.getString('MSSQL_USER');
  final password = Env.getString('MSSQL_PASSWORD');

  return DbClient(
    dsn: dsn,
    username: user,
    password: password,
    autoConnect: autoConnect,
  );
}

/// Factory to create an ODBC client targeting Oracle.
/// Reads environment variables:
/// - ORACLE_DSN
/// - ORACLE_USER
/// - ORACLE_PASSWORD
DbClient createOracleClient({bool autoConnect = false}) {
  final dsn = Env.getString('ORACLE_DSN');
  final user = Env.getString('ORACLE_USER');
  final password = Env.getString('ORACLE_PASSWORD');

  return DbClient(
    dsn: dsn,
    username: user,
    password: password,
    autoConnect: autoConnect,
  );
}

/// Factory to create an ODBC client targeting PostgreSQL.
/// Reads environment variables:
/// - POSTGRES_DSN
/// - POSTGRES_USER
/// - POSTGRES_PASSWORD
DbClient createPostgresClient({bool autoConnect = false}) {
  final dsn = Env.getString('POSTGRES_DSN');
  final user = Env.getString('POSTGRES_USER');
  final password = Env.getString('POSTGRES_PASSWORD');

  return DbClient(
    dsn: dsn,
    username: user,
    password: password,
    autoConnect: autoConnect,
  );
}