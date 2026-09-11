class EmailAddress {
  const EmailAddress._(this.value);

  final String value;

  static EmailAddress parse(String input) {
    final normalized = input.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const FormatException('Enter a valid email address.');
    }
    return EmailAddress._(normalized);
  }

  @override
  String toString() => value;
}
