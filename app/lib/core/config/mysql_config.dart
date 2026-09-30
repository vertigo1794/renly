/// Reads the MySQL view-counter database's connection details out of an
/// environment map (normally `dotenv.env` after `.env` has been loaded) --
/// same pure-factory pattern as SupabaseConfig, but this one is genuinely
/// OPTIONAL: unlike Supabase (the app's real backend, required), the MySQL
/// view-counter is a small demo feature bolted on separately, so a missing
/// config here just disables it (MysqlViewCounterService.incrementView
/// becomes a no-op) instead of throwing and blocking app startup.
class MysqlConfig {
  final String host;
  final int port;
  final String database;
  final String user;
  final String password;

  const MysqlConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.user,
    required this.password,
  });

  /// Returns null (not a thrown error) when any required value is missing
  /// -- this feature is additive/best-effort, not load-bearing.
  static MysqlConfig? fromEnvironment(Map<String, String> env) {
    final host = env['MYSQL_HOST'];
    final portRaw = env['MYSQL_PORT'];
    final database = env['MYSQL_DATABASE'];
    final user = env['MYSQL_USER'];
    final password = env['MYSQL_PASSWORD'];

    if (host == null || host.isEmpty) return null;
    if (database == null || database.isEmpty) return null;
    if (user == null || user.isEmpty) return null;
    if (password == null || password.isEmpty) return null;

    final port = int.tryParse(portRaw ?? '3306') ?? 3306;
    return MysqlConfig(host: host, port: port, database: database, user: user, password: password);
  }
}
