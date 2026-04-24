// Web stub: no filesystem, logLine only hits the console.
//
// ignore_for_file: avoid_print

String? initLogger() => null;

void logLine(String line) {
  print(line);
}

void closeLogger() {}
