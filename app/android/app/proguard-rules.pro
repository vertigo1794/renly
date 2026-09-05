# Stripe's Android SDK ships an OPTIONAL push-provisioning (Google/Apple
# Wallet card provisioning) code path that references a React Native
# wrapper class (com.reactnativestripesdk...) this pure-Flutter app never
# uses. R8 treats a missing class referenced by kept code as a hard build
# failure by default (not just a warning) -- this project doesn't use
# push provisioning at all, so the class genuinely isn't needed at
# runtime; -dontwarn (R8's own suggested fix, from
# build/app/outputs/mapping/release/missing_rules.txt) tells it to stop
# treating the missing reference as fatal.
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivity$f
