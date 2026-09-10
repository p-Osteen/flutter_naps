/// Supplies the sequence number (NS) that links a request to its response,
/// and a confirmation to the payment it confirms.
///
/// This is an interface rather than a counter field because NS has to survive
/// the things a kiosk does: a new transaction, a new controller, an app
/// restart, a power cut. Holding it in a freshly constructed SDK object means
/// every payment reuses the same number — which is what this SDK did before,
/// emitting NS=000002 for every transaction it ever made.
abstract class NapsSequenceStore {
  /// Abstract const constructor to allow subclassing.
  const NapsSequenceStore();

  /// Allocates the next sequence number, persisting it before it is used.
  Future<int> next();

  /// The most recently allocated number, without allocating another.
  Future<int> current();
}

/// Wraps the counter arithmetic so implementations only have to persist an int.
class NapsSequence {
  /// Private constructor to prevent instantiation of this utility class.
  NapsSequence._();

  /// NS is 6 characters, so the counter runs 1..999999 and wraps.
  static const int max = 999999;

  /// Advances [value] to the next sequence number in the 1..999999 range,
  /// wrapping to 1 if the maximum is exceeded.
  static int advance(int value) {
    final next = (value + 1) % (max + 1);
    return next == 0 ? 1 : next;
  }

  /// Formats a sequence number as the 6-character NS field.
  static String format(int value) => value.toString().padLeft(6, '0');
}

/// Non-persistent store. Correct for tests and for one-shot tooling; wrong for
/// a kiosk, which should back the counter with durable storage.
class InMemoryNapsSequenceStore implements NapsSequenceStore {
  int _value;

  /// Creates an in-memory sequence store, optionally starting from [initialValue].
  InMemoryNapsSequenceStore([int initialValue = 0]) : _value = initialValue;

  @override
  Future<int> current() async => _value;

  @override
  Future<int> next() async {
    _value = NapsSequence.advance(_value);
    return _value;
  }
}

/// Store backed by caller-supplied read and write callbacks.
///
/// Lets the host application persist NS wherever it already keeps state
/// (SharedPreferences, a settings service, a database) without this package
/// taking a dependency on any of them. The write is awaited *before* the
/// number is handed out, so a crash mid-transaction cannot reissue it.
class CallbackNapsSequenceStore implements NapsSequenceStore {
  /// Callback function to asynchronously read the persisted sequence number.
  final Future<int?> Function() read;

  /// Callback function to asynchronously persist the updated sequence number.
  final Future<void> Function(int value) write;

  int? _cached;

  /// Creates a callback-backed sequence store with [read] and [write] handlers.
  CallbackNapsSequenceStore({required this.read, required this.write});

  @override
  Future<int> current() async => _cached ??= (await read()) ?? 0;

  @override
  Future<int> next() async {
    final value = NapsSequence.advance(await current());
    await write(value);
    _cached = value;
    return value;
  }
}
