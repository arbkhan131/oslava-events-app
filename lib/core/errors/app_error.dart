sealed class AppError {
  const AppError(this.message);

  final String message;
}

final class ConfigurationError extends AppError {
  const ConfigurationError(super.message);
}

final class UnexpectedAppError extends AppError {
  const UnexpectedAppError(super.message);
}
