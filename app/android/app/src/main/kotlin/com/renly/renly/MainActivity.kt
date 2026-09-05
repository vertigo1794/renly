package com.renly.renly

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (NOT FlutterActivity) is a hard requirement of
// flutter_stripe. Stripe's PaymentSheet is an AndroidX
// BottomSheetDialogFragment, so it needs a FragmentActivity host with a
// real FragmentManager. Under the default FlutterActivity the sheet
// cannot be shown at all -- presentPaymentSheet() fails at runtime and
// the entire upgrade flow is unreachable on Android, with nothing in the
// Dart code to hint at why.
//
// local_auth (biometric sign-in) now depends on this too:
// local_auth_android's BiometricPrompt needs a FragmentActivity host, so
// downgrading this back to FlutterActivity would break BOTH the Stripe
// PaymentSheet and the biometric prompt.
class MainActivity : FlutterFragmentActivity()
