import 'dart:convert';
import 'dart:io';

import 'package:proxypin/storage/path.dart';

class AutoBackupLog {
  static const fileName = 'auto_backup.log';

  static Future<void> info(String message, [Map<String, Object?> data = const {}]) => _write('INFO', message, data);

  static Future<void> warn(String message, [Map<String, Object?> data = const {}]) => _write('WARN', message, data);

  static Future<void> error(String message, Object error, StackTrace? stackTrace,
          [Map<String, Object?> data = const {}]) =>
      _write('ERROR', message, {
        ...data,
        'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      });

  static Future<void> _write(String level, String message, Map<String, Object?> data) async {
    try {
      final file = await Paths.getPath(fileName);
      final entry = {
        'time': DateTime.now().toIso8601String(),
        'level': level,
        'message': message,
        if (data.isNotEmpty) 'data': data,
      };
      await file.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never break backup flow.
    }
  }
}
