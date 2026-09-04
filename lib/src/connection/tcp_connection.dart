import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/message.dart';
import 'connection.dart';
import 'frame_buffer.dart';

class NapsTcpConnection implements NapsConnection {
  final String host;
  final int port;
  final Duration defaultTimeout;

  /// Receives every frame in and out, already redacted. See [NapsFrameLog].
  final NapsFrameLogger? onFrame;

  Socket? _socket;
  final NapsFrameBuffer _buffer = NapsFrameBuffer();
  Completer<NapsMessage>? _completer;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _settleTimer;

  NapsTcpConnection({
    required this.host,
    this.port = 4444,
    this.defaultTimeout = const Duration(seconds: 30),
    this.onFrame,
  });

  @override
  String get transportDescription => 'wifi $host:$port';

  @override
  bool get isConnected => _socket != null;

  @override
  Future<bool> connect() async {
    if (isConnected) return true;
    try {
      _socket = await Socket.connect(host, port, timeout: defaultTimeout);
      _buffer.clear();
      _subscription = _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );
      return true;
    } catch (_) {
      await disconnect();
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _settleTimer?.cancel();
    _settleTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _buffer.clear();

    final pending = _completer;
    _completer = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(SocketException('Socket disconnected.'));
    }
  }

  @override
  Future<void> send(NapsMessage message) async {
    if (!isConnected) {
      throw SocketException('Cannot send message, TCP connection is not open.');
    }
    final bytes = message.toFrameBytes();
    onFrame?.call(NapsFrameLog.of(NapsFrameDirection.outbound, bytes));
    _socket!.add(bytes);
    await _socket!.flush();
  }

  @override
  Future<NapsMessage> receive({Duration? timeout}) async {
    if (!isConnected) {
      throw SocketException(
        'Cannot receive message, TCP connection is not open.',
      );
    }

    // Single-flight. Two concurrent receives on one terminal is always a bug:
    // silently cancelling the older one hides it and loses its response.
    if (_completer != null && !_completer!.isCompleted) {
      throw StateError(
        'A receive is already pending on this NAPS connection; '
        'operations must be serialised.',
      );
    }

    final buffered = _takeNow();
    if (buffered != null) return buffered;

    final completer = Completer<NapsMessage>();
    _completer = completer;

    final effectiveTimeout = timeout ?? defaultTimeout;

    return completer.future.timeout(
      effectiveTimeout,
      onTimeout: () {
        if (_completer == completer) _completer = null;
        // Last resort before giving up: the terminal may have sent a whole
        // receipt without its '?' terminator. Accept it, flagged, rather than
        // discard a response to a transaction that has already been approved.
        final salvaged = _takeNow(salvage: true);
        if (salvaged != null) return salvaged;
        throw TimeoutException(
          'Timed out waiting for NAPS response after $effectiveTimeout '
          '(${_buffer.length} bytes buffered).',
        );
      },
    );
  }

  /// A NAPS frame carries no delimiter, so a response with no DP terminator is
  /// only "complete" by inference from its envelope. Letting the stream settle
  /// for a beat before acting on one costs nothing and closes the race where a
  /// frame split across segments is delivered with its later fields missing.
  static const Duration _undelimitedSettle = Duration(milliseconds: 120);

  /// Takes a frame that is already buffered. Used on entry to [receive], where
  /// the bytes arrived before the caller asked for them, and on the timeout
  /// path with [salvage] set.
  NapsMessage? _takeNow({bool salvage = false}) {
    final peek = _buffer.peekFrame(allowUnterminatedDp: salvage);
    if (peek == null) return null;
    _buffer.commit(peek.end);
    final raw = peek.message.rawFrame;
    if (raw != null) {
      onFrame?.call(NapsFrameLog.of(NapsFrameDirection.inbound, raw));
    }
    return peek.message;
  }

  /// Called as bytes arrive. Delivers to a waiting [receive] once the frame
  /// looks whole, deferring undelimited frames by [_undelimitedSettle].
  void _tryDeliver({bool settled = false}) {
    final pending = _completer;
    if (pending == null || pending.isCompleted) {
      // Nothing is waiting yet. Leave the frame buffered so the next
      // receive() picks it up rather than dropping it on the floor.
      return;
    }

    final peek = _buffer.peekFrame();
    if (peek == null) return;

    if (!peek.delimited && !settled) {
      _settleTimer?.cancel();
      _settleTimer = Timer(
        _undelimitedSettle,
        () => _tryDeliver(settled: true),
      );
      return;
    }

    _settleTimer?.cancel();
    _settleTimer = null;
    _buffer.commit(peek.end);
    final raw = peek.message.rawFrame;
    if (raw != null) {
      onFrame?.call(NapsFrameLog.of(NapsFrameDirection.inbound, raw));
    }
    _completer = null;
    pending.complete(peek.message);
  }

  void _onData(Uint8List data) {
    // No decoding here. Bytes are accumulated and framed as bytes; a
    // multi-byte character split across two TCP segments used to throw here
    // and tear down the connection mid-transaction.
    _buffer.add(data);
    _tryDeliver();
  }

  void _onError(Object error) {
    final pending = _completer;
    _completer = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(error);
    }
    disconnect();
  }

  void _onDone() {
    disconnect();
  }

  /// Reconnects with exponential backoff. Delays: 500ms, 1s, 2s, ...
  @override
  Future<bool> reconnect({int maxAttempts = 3}) async {
    await disconnect();
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
      await Future.delayed(delay);
      if (await connect()) return true;
    }
    return false;
  }
}
