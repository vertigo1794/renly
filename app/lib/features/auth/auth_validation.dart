/// Pure form-validation logic for the auth/registration screens. No
/// Flutter, no Supabase -- fully unit-testable.
class AuthValidation {
  AuthValidation._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _icPattern = RegExp(r'^\d{6}-\d{2}-\d{4}$');
  static final RegExp _phonePattern = RegExp(r'^\d{2,3}-\d{6,8}$');

  static bool isValidEmail(String email) => _emailPattern.hasMatch(email);

  static bool isValidPassword(String password) => password.length >= 8;

  static bool passwordsMatch(String password, String confirmPassword) =>
      password.isNotEmpty && password == confirmPassword;

  static bool isValidIcNumber(String icNumber) => _icPattern.hasMatch(icNumber);

  static bool isValidPhoneNumber(String phoneNumber) => _phonePattern.hasMatch(phoneNumber);
}
