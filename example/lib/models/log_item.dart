import 'package:naps_flutter/naps_flutter.dart';

class LogItem {
  final DateTime timestamp;
  final String text;
  final NapsFrameDirection? direction;
  final bool isError;
  final bool isSuccess;
  final NapsMessage? rawMessage;
  final NapsFrameLog? frameLog;

  const LogItem({
    required this.timestamp,
    required this.text,
    this.direction,
    this.isError = false,
    this.isSuccess = false,
    this.rawMessage,
    this.frameLog,
  });
}
