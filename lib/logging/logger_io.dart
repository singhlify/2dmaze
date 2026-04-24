// IO implementation: every logLine goes to stdout AND appends to a file.
//
// Default path is `windows.logs.txt` in the current working directory
// (i.e. the repo root when you run from there). Override with the
// MAZE_LOG_FILE environment variable at runtime.
//
// File mode is append, with a `=== session start: <ISO-8601> ===`
// marker between runs so you can tell them apart.

import 'dart:io';

// ignore_for_file: avoid_print

IOSink? _sink;
String? _path;

/// Opens the log file and returns the absolute path we're writing to,
/// or null if the path couldn't be opened (permission, etc.). Still
/// prints to stdout in that case; file logging is best-effort.
String? initLogger() {
  if (_sink != null) return _path;
  try {
    final path = Platform.environment['MAZE_LOG_FILE'] ?? 'windows.logs.txt';
    final file = File(path);
    _sink = file.openWrite(mode: FileMode.append);
    _path = file.absolute.path;
    _sink!.writeln(
        '\n=== session start: ${DateTime.now().toIso8601String()} ===');
    return _path;
  } catch (e) {
    _sink = null;
    _path = null;
    print('[logger] Could not open log file: $e');
    return null;
  }
}

void logLine(String line) {
  print(line);
  _sink?.writeln(line);
}

void closeLogger() {
  try {
    _sink?.flush();
    _sink?.close();
  } catch (_) {
    // best-effort
  }
  _sink = null;
}
