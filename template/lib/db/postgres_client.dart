import 'package:postgres/postgres.dart';
import 'package:modular_api/modular_api.dart';

/// PostgreSQL database client with connection pooling.
///
/// This client manages connections to PostgreSQL and provides
/// helper methods for executing queries and transactions.
///
/// Usage:
/// ```dart
/// final db = PostgresClient();
/// await db.connect();
///
/// final users = await db.query(
///   'SELECT * FROM auth.user WHERE username = @username',
///   {'username': 'example'}
/// );
///
/// await db.close();
/// ```
class PostgresClient {
  Connection? _connection;
  late final String host;
  late final int port;
  late final String database;
  late final String username;
  late final String password;

  /// Creates a PostgreSQL client with configuration from environment variables.
  PostgresClient({
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
  }) {
    this.host = host ?? Env.getString('POSTGRES_HOST');
    this.port = port ?? Env.getInt('POSTGRES_PORT');
    this.database = database ?? Env.getString('POSTGRES_DB');
    this.username = username ?? Env.getString('POSTGRES_USER');
    this.password = password ?? Env.getString('POSTGRES_PASSWORD');
  }

  /// Establishes connection to PostgreSQL database.
  Future<void> connect() async {
    if (_connection != null) {
      return; // Already connected
    }

    _connection = await Connection.open(
      Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
      settings: const ConnectionSettings(
        sslMode: SslMode.disable, // Use SslMode.require in production
      ),
    );
  }

  /// Ensures connection is established before executing queries.
  Future<void> _ensureConnected() async {
    if (_connection == null) {
      await connect();
    }
  }

  /// Executes a query and returns the results.
  ///
  /// [sql] - SQL query with named parameters (e.g., @username)
  /// [parameters] - Map of parameter names to values
  ///
  /// Returns a list of rows as maps.
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    await _ensureConnected();

    final result = await _connection!.execute(
      Sql.named(sql),
      parameters: parameters,
    );

    return result.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < row.length; i++) {
        final columnName = result.schema.columns[i].columnName ?? 'column_$i';
        map[columnName] = row[i];
      }
      return map;
    }).toList();
  }

  /// Executes a command (INSERT, UPDATE, DELETE) and returns affected rows count.
  ///
  /// [sql] - SQL command with named parameters
  /// [parameters] - Map of parameter names to values
  ///
  /// Returns the number of affected rows.
  Future<int> execute(String sql, [Map<String, dynamic>? parameters]) async {
    await _ensureConnected();

    final result = await _connection!.execute(
      Sql.named(sql),
      parameters: parameters,
    );

    return result.affectedRows;
  }

  /// Executes a query that returns a single row.
  ///
  /// Returns null if no rows are found.
  Future<Map<String, dynamic>?> queryOne(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    final results = await query(sql, parameters);
    return results.isEmpty ? null : results.first;
  }

  /// Executes multiple queries within a transaction.
  ///
  /// If any query fails, the entire transaction is rolled back.
  ///
  /// Usage:
  /// ```dart
  /// await db.transaction((txn) async {
  ///   await txn.execute(Sql.named('INSERT INTO ...'));
  ///   await txn.execute(Sql.named('UPDATE ...'));
  /// });
  /// ```
  Future<T> transaction<T>(Future<T> Function(TxSession) action) async {
    await _ensureConnected();

    return await _connection!.runTx((txn) async {
      return await action(txn);
    });
  }

  /// Closes the database connection.
  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }

  /// Checks if the connection is open.
  bool get isConnected => _connection != null;
}
