import 'dart:async';

/// A lightweight token that can be used to cancel an in-progress payment
/// from the UI (e.g., a "Cancel" button on the kiosk screen).
///
/// Pass an instance to [NapsSdk.pay] to allow the caller to abort the
/// 2-minute card-read wait. When [cancel] is called, the SDK's pending
/// receive is raced against this token and a decline result with code
/// `source: NapsResultSource.cancelled` is returned.
class NapsCancelToken {
  /// Creates a [NapsCancelToken].
  NapsCancelToken();

  final _completer = Completer<void>();

  /// Returns `true` if [cancel] has already been called.
  bool get isCancelled => _completer.isCompleted;

  /// Cancels the in-progress operation. Safe to call multiple times.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// A future that completes when [cancel] is called.
  Future<void> get onCancel => _completer.future;
}
