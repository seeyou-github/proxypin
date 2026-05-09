import 'dart:io';

import 'package:flutter/services.dart';
import 'package:proxypin/storage/auto_backup_log.dart';

class AutoBackupStorage {
  static const MethodChannel _channel = MethodChannel('com.proxy/autoBackupStorage');

  static bool get supportsSafDirectory => Platform.isAndroid;

  static bool isSafDirectory(String path) => path.startsWith('content://');

  static Future<String?> selectDirectory() async {
    if (!supportsSafDirectory) {
      await AutoBackupLog.warn('SAF directory selection requested on unsupported platform');
      return null;
    }
    await AutoBackupLog.info('Android SAF directory selection started');
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('selectDirectory');
      final path = result?['uri'] as String?;
      await AutoBackupLog.info('Android SAF directory selection finished', {
        'selected': path != null,
        if (path != null) 'directoryUri': path,
        if (result != null) 'nativeResult': Map<String, Object?>.from(result),
      });
      return path;
    } catch (e, t) {
      await AutoBackupLog.error('Android SAF directory selection failed', e, t);
      rethrow;
    }
  }

  static Future<bool> writeFiles(String directoryUri, Map<String, String> files) async {
    if (!supportsSafDirectory || !isSafDirectory(directoryUri)) {
      await AutoBackupLog.warn('Android SAF write skipped because directory is not supported', {
        'supportsSafDirectory': supportsSafDirectory,
        'directoryUri': directoryUri,
      });
      return false;
    }

    await AutoBackupLog.info('Android SAF write started', {
      'directoryUri': directoryUri,
      'fileNames': files.keys.toList(),
      'fileSizes': files.map((key, value) => MapEntry(key, value.length)),
    });
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('writeFiles', {
        'directoryUri': directoryUri,
        'files': files,
      });
      final success = result?['success'] == true;
      await AutoBackupLog.info('Android SAF write finished', {
        'success': success,
        'directoryUri': directoryUri,
        if (result != null) 'nativeResult': Map<String, Object?>.from(result),
      });
      return success;
    } catch (e, t) {
      await AutoBackupLog.error('Android SAF write failed', e, t, {'directoryUri': directoryUri});
      rethrow;
    }
  }
}
