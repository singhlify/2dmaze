// Cross-platform logger: always prints to stdout, and on desktop also
// appends to a file. See logger_io.dart / logger_stub.dart.
//
// Conditional import: on web the stub is used (no dart:io); on desktop
// the IO impl is used.

export 'logger_stub.dart'
    if (dart.library.io) 'logger_io.dart';
