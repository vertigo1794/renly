// app/lib/features/auth/auth_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';
import 'models/negotiator.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(Supabase.instance.client);
});

/// Emits on every sign-in/sign-out. `onAuthStateChange` emits the current
/// session state immediately on subscribe, so this has a value as soon as
/// the app starts (not stuck in "loading" until the first real event).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final negotiatorProfileProvider = FutureProvider.family<Negotiator?, String>((ref, negotiatorId) {
  return ref.watch(authRepositoryProvider).fetchOwnNegotiator(negotiatorId);
});

/// Whether this device supports biometric authentication at all (hardware
/// + enrollment) -- device-local capability, NOT negotiator-scoped (unlike
/// settings_providers.dart's pattern, which gates server-backed prefs on
/// currentNegotiatorIdProvider).
final biometricAvailableProvider = FutureProvider<bool>((ref) {
  return ref.watch(authRepositoryProvider).isBiometricAvailable();
});

/// Whether a biometric-gated refresh token is currently stored on this
/// device -- LoginScreen's biometric button only renders when this
/// resolves true.
final biometricLoginEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(authRepositoryProvider).hasBiometricLoginEnabled();
});
