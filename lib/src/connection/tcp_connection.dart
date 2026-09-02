import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../protocol/message.dart';
import 'connection.dart';

class NapsTcpConnection implements NapsConnection {
  final String host;
  final int port;
  final Duration defaultTimeout;

  Socket? _socket;
  String _receiveBuffer = '';
  Completer<NapsMessage>? _completer;
  StreamSubscription<List<int>>? _subscription;

  NapsTcpConnection({
    required this.host,
    this.port = 4444,
    this.defaultTimeout = const Duration(seconds: 30),
  });

  @override
  bool get isConnected => _socket != null;

  @override
  Future<bool> connect() async {
    if (isConnected) return true;
    try {
      _socket = await Socket.connect(host, port, timeout: defaultTimeout);
      _receiveBuffer = '';
      _subscription = _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );
      return true;
    } catch (e) {
      await disconnect();
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _receiveBuffer = '';
    
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError(SocketException('Socket disconnected.'));
      _completer = null;
    }
  }

  @override
  Future<void> send(NapsMessage message) async {
    if (!isConnected) {
      throw SocketException('Cannot send message, TCP connection is not open.');
    }
    final frame = message.toFrame();
    _socket!.write(frame);
    await _socket!.flush();
  }

  @override
  Future<NapsMessage> receive({Duration? timeout}) async {
    if (!isConnected) {
      throw SocketException('Cannot receive message, TCP connection is not open.');
    }

    // Check if we already have a complete frame in the buffer
    final parsedMsg = _tryParseFrameFromBuffer();
    if (parsedMsg != null) {
      return parsedMsg;
    }

    // Otherwise, create a completer and wait for data
    if (_completer != null && !_completer!.isCompleted) {
      // If there is an existing pending receive, reuse/fail or serialize it.
      // For simplicity, we fail the old one and register the new one.
      _completer!.completeError(StateError('New receive request registered, old one cancelled.'));
    }

    final completer = Completer<NapsMessage>();
    _completer = completer;

    final effectiveTimeout = timeout ?? defaultTimeout;
    
    return completer.future.timeout(
      effectiveTimeout,
      onTimeout: () {
        if (_completer == completer) {
          _completer = null;
        }
        throw TimeoutException('Timed out waiting for NAPS response after $effectiveTimeout.');
      },
    );
  }

  void _onData(List<int> data) {
    try {
      final text = utf8.decode(data);
      _receiveBuffer += text;

      final message = _tryParseFrameFromBuffer();
      if (message != null) {
        if (_completer != null && !_completer!.isCompleted) {
          _completer!.complete(message);
          _completer = null;
        }
      }
    } catch (e) {
      _onError(e);
    }
  }

  void _onError(dynamic error) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError(error);
      _completer = null;
    }
    disconnect();
  }

  void _onDone() {
    disconnect();
  }

  /// Attempts to parse a single complete NAPS frame from the front of the receive buffer.
  /// If successful, removes the frame characters from [_receiveBuffer] and returns [NapsMessage].
  /// If incomplete, returns null.
  NapsMessage? _tryParseFrameFromBuffer() {
    if (_receiveBuffer.isEmpty) return null;

    final frameLen = _getExpectedFrameLength(_receiveBuffer);
    if (frameLen > 0) {
      final frameText = _receiveBuffer.substring(0, frameLen);
      _receiveBuffer = _receiveBuffer.substring(frameLen);
      
      try {
        return NapsMessage.fromFrame(frameText);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Determines the length of a complete TLV frame inside the text, or returns -1 if incomplete.
  int _getExpectedFrameLength(String text) {
    int index = 0;
    while (index < text.length) {
      if (index + 6 > text.length) {
        // Real EPT hardware can append trailing artifact bytes after the
        // last valid field; once we've parsed something, treat the rest as
        // garbage to discard rather than waiting forever for more data.
        return index > 0 ? text.length : -1;
      }
      final lenStr = text.substring(index + 3, index + 6);
      final len = int.tryParse(lenStr);
      if (len == null) {
        return index > 0 ? text.length : -1; // Malformed/artifact tag
      }
      if (index + 6 + len > text.length) {
        return -1; // Incomplete value string
      }
      index += 6 + len;
    }
    return index; // Valid frame consumed up to this index
  }

  /// Reconnects with exponential backoff.
  /// Delays: 500ms, 1s, 2s, ... doubling on each attempt.
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
