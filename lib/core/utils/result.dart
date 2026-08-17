/// A minimal `Result` type used to model operation outcomes across service
/// boundaries without relying on exceptions for control flow.
library;

import '../errors/app_failure.dart';

/// Either a successful [Ok] with a value or a failed [Err] with an
/// [AppFailure].
sealed class Result<T> {
  const Result();
}

/// Success branch of a [Result].
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

/// Failure branch of a [Result].
final class Err<T> extends Result<T> {
  const Err(this.failure);

  final AppFailure failure;
}