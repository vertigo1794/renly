import 'package:mysql_client/mysql_client.dart';

import '../../core/config/mysql_config.dart';

/// Literal MySQL Database Integration -- connects DIRECTLY to a real cloud
/// MySQL instance (Clever Cloud) over the MySQL wire protocol via
/// `mysql_client`, genuinely separate from the app's Supabase/PostgreSQL
/// backend. Tracks nothing sensitive: just a per-listing view counter.
///
/// Every call is best-effort, mirroring this codebase's push-notification
/// pattern: a missing config or a network hiccup must never surface to the
/// UI or block it, it just means the view counter silently doesn't update.
class MysqlViewCounterService {
  MysqlViewCounterService(this._config);

  final MysqlConfig? _config;

  Future<MySQLConnection?> _connect() async {
    final config = _config;
    if (config == null) return null;
    try {
      final conn = await MySQLConnection.createConnection(
        host: config.host,
        port: config.port,
        userName: config.user,
        password: config.password,
        databaseName: config.database,
        secure: true,
      );
      await conn.connect();
      return conn;
    } catch (_) {
      return null;
    }
  }

  /// Fire-and-forget: bumps the view count for [listingId], creating the
  /// row on first view. Never throws.
  Future<void> incrementView(String listingId) async {
    final conn = await _connect();
    if (conn == null) return;
    try {
      await conn.execute(
        'INSERT INTO listing_view_count (listing_id, view_count, last_viewed_at) '
        'VALUES (:id, 1, NOW()) '
        'ON DUPLICATE KEY UPDATE view_count = view_count + 1, last_viewed_at = NOW()',
        {'id': listingId},
      );
    } catch (_) {
      // best-effort, same reasoning as every other view/analytics side-call.
    } finally {
      await conn.close();
    }
  }

  /// Returns the current view count for [listingId], or null when unknown
  /// (no config, connection failure, or no rows yet).
  Future<int?> fetchViewCount(String listingId) async {
    final conn = await _connect();
    if (conn == null) return null;
    try {
      final result = await conn.execute(
        'SELECT view_count FROM listing_view_count WHERE listing_id = :id',
        {'id': listingId},
      );
      if (result.rows.isEmpty) return 0;
      final raw = result.rows.first.colByName('view_count');
      return raw == null ? 0 : int.tryParse(raw);
    } catch (_) {
      return null;
    } finally {
      await conn.close();
    }
  }
}
