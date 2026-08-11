/// Base type for all recoverable errors surfaced to the presentation layer.
///
/// Repositories convert low-level exceptions into [Failure]s so the UI never
/// has to know about Supabase / network specifics.
sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection.']);
}

class ServerFailure extends Failure {
  const ServerFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'An unexpected error occurred.']);
}

/// Maps any caught error to a short, friendly, English message safe to show
/// users — repositories that already throw a [Failure] pass their message
/// straight through; everything else (raw `SocketException`/`ClientException`
/// text, Supabase URLs, stack-trace noise) is reduced to a generic line
/// instead of being interpolated straight onto the screen.
String friendlyErrorMessage(Object error) {
  if (error is Failure) return error.message;
  final String raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network is unreachable') ||
      raw.contains('connection refused') ||
      raw.contains('connection reset') ||
      raw.contains('clientexception')) {
    return 'No internet connection. Check your network and try again.';
  }
  if (raw.contains('timeoutexception') || raw.contains('timed out')) {
    return 'That took too long. Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}
