import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../protocol/message.dart';
import 'connection.dart';

/// Concrete implementation of [NapsConnection] using serial/USB-C COM port.
class NapsSerialConnection implements NapsConnection {
  final String portName;
  final int baudRate;
  final Duration defaultTimeout;

  SerialPort? _port;
  SerialPortReader? _reader;
  String _receiveBuffer = '';
  Completer<NapsMessage>? _completer;
  StreamSubscription<Uint8List>? _subscription;

  NapsSerialConnection({
    required this.portName,
    this.baudRate = 9600,
    this.defaultTimeout = const Duration(seconds: 30),
  });

  @override
  bool get isConnected => _port != null && _port!.isOpen;

  @override
  Future<bool> connect() async {
    if (isConnected) return true;
    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        throw Exception('Failed to open NAPS serial port: $portName');
      }

      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none;
      _port!.config = config;

      _receiveBuffer = '';
      _reader = SerialPortReader(_port!);
      _subscription = _reader!.stream.listen(
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
    _reader = null;
    try {
      if (_port != null && _port!.isOpen) {
        _port!.close();
      }
    } catch (_) {}
    _port = null;
    _receiveBuffer = '';

    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError(Exception('Serial connection closed.'));
      _completer = null;
    }
  }

  @override
  Future<void> send(NapsMessage message) async {
    if (!isConnected) {
      throw Exception('Cannot send message, serial port is not open.');
    }
    final frame = message.toFrame();
    final bytes = utf8.encode(frame);
    final written = _port!.write(Uint8List.fromList(bytes));
    if (written < 0) {
      throw Exception('Failed to write to NAPS serial port.');
    }
  }

  @override
  Future<NapsMessage> receive({Duration? timeout}) async {
    if (!isConnected) {
      throw Exception('Cannot receive message, serial port is not open.');
    }

    // Check if we already have a complete frame in the buffer
    final parsedMsg = _tryParseFrameFromBuffer();
    if (parsedMsg != null) {
      return parsedMsg;
    }

    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError(
        StateError('New receive request registered, old one cancelled.'),
      );
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
        throw TimeoutException(
          'Timed out waiting for NAPS response over serial after $effectiveTimeout.',
        );
      },
    );
  }

  void _onData(Uint8List data) {
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
