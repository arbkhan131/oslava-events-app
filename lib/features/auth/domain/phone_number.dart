class PhoneNumber {
  const PhoneNumber._(this.value);

  factory PhoneNumber.parse(String input) {
    final normalized = input.trim().replaceAll(RegExp(r'[\s().-]'), '');
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(normalized)) {
      throw const FormatException('Enter a phone number in E.164 format.');
    }

    return PhoneNumber._(normalized);
  }

  final String value;
}
