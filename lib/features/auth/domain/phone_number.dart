class PhoneNumber {
  const PhoneNumber._(this.value);

  factory PhoneNumber.parse(String input) {
    final digits = input.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final indianDigits = digits.startsWith('0') && digits.length == 11
        ? digits.substring(1)
        : digits;
    final normalized = indianDigits.length == 10
        ? '+91$indianDigits'
        : indianDigits.length == 12 && indianDigits.startsWith('91')
        ? '+$indianDigits'
        : input.trim().replaceAll(RegExp(r'[\s().-]'), '');

    if (!RegExp(r'^\+91[0-9]{10}$').hasMatch(normalized)) {
      throw const FormatException(
        'Enter a valid 10 digit Indian phone number.',
      );
    }

    return PhoneNumber._(normalized);
  }

  final String value;

  String get nationalDigits => value.substring(3);

  String get authEmail => '${value.substring(1)}@phone.oslava.local';
}
