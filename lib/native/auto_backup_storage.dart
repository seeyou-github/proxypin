import 'dart:io';

import 'package:flutter/services.dart';

class AutoBackupStorage {
  static const MethodChannel _channel = MethodChannel('com.proxy/autoBackupStorage');

  static bool get supportsSafDirectory => Platform.isAndroid;

  static bool isSafDirectory(String path) => path.startsWith('content://');

  static Future<String?> selectDirectory() async {
    if (!supportsSafDirectory) {
      return null;
    }
    return _channel.invokeMethod<String>('selectDirectory');
  }

  static Future<bool> writeFiles(String directoryUri, Map<String, String> files) async {
    if (!supportsSafDirectory || !isSafDirectory(directoryUri)) {
      return false;
    }

    return await _channel.invokeMethod<bool>('writeFiles', {
          'directoryUri': directoryUri,
          'files': files,
        }) ??
        false;
  }
}
