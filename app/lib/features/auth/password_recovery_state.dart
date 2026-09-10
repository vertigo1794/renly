/// Tracks whether the app is currently in a Supabase password-recovery
/// session, i.e. the user opened it via a "reset password" email link.
///
/// This is a plain static flag rather than a Riverpod provider on purpose:
/// `AuthChangeEvent.passwordRecovery` can fire on `onAuthStateChange`
/// (main.dart's listener, set up immediately after `Supabase.initialize()`,
/// before any Riverpod container exists) before `appRouterProvider` or any
/// other provider has been read for the first time. A provider built from
/// that same stream would only see whatever event happens to be current
/// when it's first watched -- which on a cold start via deep link can
/// already be a later event, silently losing the one that matters. Reading
/// a static flag at `redirect`-time has no such subscription-order race.
///
/// Set true by main.dart's `onAuthStateChange` listener; cleared by
/// [ResetPasswordScreen] once the new password has been saved.
class PasswordRecoveryState {
  PasswordRecoveryState._();

  static bool isRecovering = false;
}
