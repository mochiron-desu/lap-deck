import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error;

  String get label => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARN',
        LogLevel.error => 'ERROR',
      };
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String format() {
    final timeStr = timestamp.toIso8601String().substring(11, 23);
    final sb = StringBuffer('[$timeStr] [${level.label.padRight(5)}] [$tag] $message');
    if (error != null) {
      sb.write('\n    Error: $error');
    }
    if (stackTrace != null) {
      sb.write('\n    Stack: $stackTrace');
    }
    return sb.toString();
  }
}

class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  static const int _maxInMemoryEntries = 500;
  static const int _maxFileSizeBytes = 1024 * 1024; // 1 MB cap

  final ListQueue<LogEntry> _memoryBuffer = ListQueue<LogEntry>(_maxInMemoryEntries);
  final ValueNotifier<int> logCounter = ValueNotifier<int>(0);

  File? _logFile;
  File? _backupLogFile;
  IOSink? _fileSink;
  bool _initialized = false;
  final List<String> _pendingFileWrites = [];

  static Future<void> init() async {
    await instance._initStorage();
  }

  Future<void> _initStorage() async {
    if (_initialized) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${docDir.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      _logFile = File('${logsDir.path}/lapdeck.log');
      _backupLogFile = File('${logsDir.path}/lapdeck.log.old');

      if (await _logFile!.exists()) {
        final length = await _logFile!.length();
        if (length > _maxFileSizeBytes) {
          if (await _backupLogFile!.exists()) {
            await _backupLogFile!.delete();
          }
          await _logFile!.rename(_backupLogFile!.path);
          _logFile = File('${logsDir.path}/lapdeck.log');
        }
      }

      _fileSink = _logFile!.openWrite(mode: FileMode.append);
      _initialized = true;

      // Flush any queued lines from early startup
      for (final line in _pendingFileWrites) {
        _fileSink?.writeln(line);
      }
      _pendingFileWrites.clear();
      await _fileSink?.flush();
    } catch (e, st) {
      developer.log(
        'Failed to initialize AppLogger file sink: $e',
        name: 'LAPDECK',
        error: e,
        stackTrace: st,
      );
    }
  }

  static void debug(String tag, String message) {
    instance._log(LogLevel.debug, tag, message);
  }

  static void info(String tag, String message) {
    instance._log(LogLevel.info, tag, message);
  }

  static void warning(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    instance._log(LogLevel.warning, tag, message, error, stackTrace);
  }

  static void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    instance._log(LogLevel.error, tag, message, error, stackTrace);
  }

  void _log(
    LogLevel level,
    String tag,
    String message, [
    Object? errorObj,
    StackTrace? stackTraceObj,
  ]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: errorObj?.toString(),
      stackTrace: stackTraceObj?.toString(),
    );

    // 1. In-memory buffer
    if (_memoryBuffer.length >= _maxInMemoryEntries) {
      _memoryBuffer.removeFirst();
    }
    _memoryBuffer.addLast(entry);
    logCounter.value++;

    // 2. Android Logcat & Developer console
    final formatted = entry.format();
    developer.log(
      message,
      name: 'LAPDECK',
      time: entry.timestamp,
      level: _levelToInt(level),
      error: errorObj,
      stackTrace: stackTraceObj,
    );

    // Also debugPrint so standard adb logcat -s flutter:V catches it
    debugPrint('[LAPDECK][${level.label}][$tag] $message');
    if (errorObj != null) {
      debugPrint('[LAPDECK][${level.label}][$tag] Error: $errorObj');
    }

    // 3. Persistent log file
    if (_initialized && _fileSink != null) {
      try {
        _fileSink!.writeln(formatted);
      } catch (_) {}
    } else {
      _pendingFileWrites.add(formatted);
    }
  }

  int _levelToInt(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      };

  List<LogEntry> getRecentEntries({
    LogLevel? minLevel,
    String? tagFilter,
  }) {
    var entries = _memoryBuffer.toList();
    if (minLevel != null) {
      final minVal = _levelToInt(minLevel);
      entries = entries.where((e) => _levelToInt(e.level) >= minVal).toList();
    }
    if (tagFilter != null && tagFilter.isNotEmpty && tagFilter != 'ALL') {
      final filterLower = tagFilter.toLowerCase();
      entries = entries.where((e) => e.tag.toLowerCase().contains(filterLower)).toList();
    }
    return entries.reversed.toList();
  }

  Future<String> getLogFilePath() async {
    if (_logFile != null) return _logFile!.path;
    final docDir = await getApplicationDocumentsDirectory();
    return '${docDir.path}/logs/lapdeck.log';
  }

  Future<String> exportAllLogsText() async {
    final sb = StringBuffer();
    if (_backupLogFile != null && await _backupLogFile!.exists()) {
      try {
        sb.writeln('=== BACKUP LOG ARCHIVE ===');
        sb.writeln(await _backupLogFile!.readAsString());
        sb.writeln('=== CURRENT ACTIVE LOG ===');
      } catch (_) {}
    }
    if (_logFile != null && await _logFile!.exists()) {
      try {
        sb.writeln(await _logFile!.readAsString());
      } catch (_) {}
    } else if (_memoryBuffer.isNotEmpty) {
      for (final e in _memoryBuffer) {
        sb.writeln(e.format());
      }
    }
    return sb.toString();
  }

  Future<void> clear() async {
    _memoryBuffer.clear();
    logCounter.value++;
    try {
      await _fileSink?.flush();
      await _fileSink?.close();
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
      if (_backupLogFile != null && await _backupLogFile!.exists()) {
        await _backupLogFile!.delete();
      }
      if (_logFile != null) {
        _fileSink = _logFile!.openWrite(mode: FileMode.append);
      }
    } catch (_) {}
  }
}
