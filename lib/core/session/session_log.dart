import 'package:flutter/foundation.dart';

/// Ring buffer of recent session events for a simple log panel.
class SessionLog extends ChangeNotifier {
  SessionLog({this.capacity = 200});

  final int capacity;
  final List<SessionLogEntry> _entries = [];

  List<SessionLogEntry> get entries => List.unmodifiable(_entries);

  void add(String message, {SessionLogLevel level = SessionLogLevel.info}) {
    _entries.add(
      SessionLogEntry(
        at: DateTime.now(),
        message: message,
        level: level,
      ),
    );
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

enum SessionLogLevel { info, warn, error }

class SessionLogEntry {
  const SessionLogEntry({
    required this.at,
    required this.message,
    required this.level,
  });

  final DateTime at;
  final String message;
  final SessionLogLevel level;
}

final sessionLog = SessionLog();
