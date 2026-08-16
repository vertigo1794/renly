import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/config/supabase_config.dart';

void main() {
  group('SupabaseConfig.fromEnvironment', () {
    test('returns config when both keys present', () {
      final config = SupabaseConfig.fromEnvironment({
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'test-anon-key',
      });

      expect(config.url, 'https://example.supabase.co');
      expect(config.anonKey, 'test-anon-key');
    });

    test('throws ArgumentError when SUPABASE_URL missing', () {
      expect(
        () => SupabaseConfig.fromEnvironment({'SUPABASE_ANON_KEY': 'x'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when SUPABASE_ANON_KEY missing', () {
      expect(
        () => SupabaseConfig.fromEnvironment({'SUPABASE_URL': 'https://x.supabase.co'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
