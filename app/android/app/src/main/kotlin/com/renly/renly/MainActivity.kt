package com.renly.renly

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (NOT FlutterActivity) is a hard requirement of
// flutter_stripe. Stripe's PaymentSheet is an AndroidX
// BottomSheetDialogFragment, so it needs a FragmentActivity host with a
// real FragmentManager. Under the default FlutterActivity the sheet
// cannot be shown at all -- presentPaymentSheet() fails at runtime and
// the entire upgrade flow is unreachable on Android, with nothing in the
// Dart code to hint at why.
class MainActivity : FlutterFragmentActivity()
