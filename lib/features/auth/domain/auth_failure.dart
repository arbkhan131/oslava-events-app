class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

class PhoneConfirmationRequired extends AuthFailure {
  const PhoneConfirmationRequired()
    : super('Verify the code sent to your email, then finish your profile.');
}
