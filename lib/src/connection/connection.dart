import '../protocol/message.dart';

abstract class NapsConnection {
  /// Establish connection to the EPT terminal.
  Future<bool> connect();

  /// Terminate connection to the EPT terminal.
  Future<void> disconnect();

  /// Returns true if currently connected.
  bool get isConnected;

  /// Encodes and sends a [NapsMessage] to the EPT.
  Future<void> send(NapsMessage message);

  /// Waits for and receives a [NapsMessage] response from the EPT.
  /// An optional [timeout] can be specified to override default connection timeouts.
  Future<NapsMessage> receive({Duration? timeout});

  /// Attempts to re-establish the connection after a transient disconnect.
  /// Subclasses may override for reconnect-with-backoff behavior.
  /// Returns true if reconnection was successful within [maxAttempts].
  Future<bool> reconnect({int maxAttempts = 3}) async {
    await disconnect();
    return connect();
  }
}
