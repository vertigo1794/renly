/// Reads Supabase connection details out of an environment map (normally
/// `dotenv.env` after `.env` has been loaded). Kept as a pure factory so it
/// can be unit-tested without touching flutter_dotenv or the network.
class SupabaseConfig {
  final String url;
  final String anonKey;

  const SupabaseConfig({required this.url, required this.anonKey});

  factory SupabaseConfig.fromEnvironment(Map<String, String> env) {
    final url = env['SUPABASE_URL'];
    final anonKey = env['SUPABASE_ANON_KEY'];

    if (url == null || url.isEmpty) {
      throw ArgumentError(
        'SUPABASE_URL missing. Copy app/.env.example to app/.env and fill in your Supabase project values.',
      );
    }
    if (anonKey == null || anonKey.isEmpty) {
      throw ArgumentError(
        'SUPABASE_ANON_KEY missing. Copy app/.env.example to app/.env and fill in your Supabase project values.',
      );
    }

    return SupabaseConfig(url: url, anonKey: anonKey);
  }
}
