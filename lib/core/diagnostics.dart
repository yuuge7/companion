import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Bounded, local-only error history. Never includes shelf data or URLs.
abstract final class Diagnostics {
  static File? _file;
  static String _log = '';
  static Future<void> _writes = Future.value();
  static Future<void> initialize() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/diagnostics.txt');
      if (await _file!.exists()) _log = await _file!.readAsString();
    } catch (_) {
      /* Logging must not prevent startup. */
    }
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      record(
        details.exception,
        details.stack ?? StackTrace.current,
        source: 'Flutter',
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, source: 'platform');
      return true;
    };
  }

  static void record(Object error, StackTrace stack, {String source = 'app'}) {
    final frames = stack
        .toString()
        .split('\n')
        .where((s) => s.contains('package:companion/'))
        .take(8)
        .join('\n');
    _log +=
        '${DateTime.now().toUtc().toIso8601String()} $source: ${error.runtimeType}\n$frames\n';
    if (_log.length > 24000) _log = _log.substring(_log.length - 24000);
    final copy = _log;
    _writes = _writes
        .then((_) async {
          if (_file != null) await _file!.writeAsString(copy, flush: true);
        })
        .catchError((_) {});
  }

  static Future<String> copyReport() async {
    try {
      if (_file == null) return report;
      final native = File('${_file!.parent.path}/native-diagnostics.txt');
      if (await native.exists()) {
        return '$report\nAndroid background errors\n${await native.readAsString()}';
      }
    } catch (_) {
      /* The Flutter log is still useful if the native log is unreadable. */
    }
    return report;
  }

  static String get report =>
      'Companion · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n${_log.isEmpty ? 'No errors recorded.' : _log}';
}
