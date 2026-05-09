import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/native/auto_backup_storage.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/ui/configuration.dart';

class AutoBackup {
  static const favoritesFileName = 'AutoBackup_favorites.json';
  static const blackHostFiltersFileName = 'AutoBackup_host-filters-black.config';
  static const whiteHostFiltersFileName = 'AutoBackup_host-filters-white.config';

  static final StreamController<void> _backupDirectoryInvalidController = StreamController<void>.broadcast();
  static bool _isBackingUp = false;
  static bool _backupPending = false;

  static Stream<void> get onBackupDirectoryInvalid => _backupDirectoryInvalidController.stream;

  static Future<bool> backupAll({String? favoritesJson}) async {
    final backupDirectory = AppConfiguration.current?.autoBackupDirectory;
    if (backupDirectory == null || backupDirectory.trim().isEmpty) {
      return false;
    }

    if (_isBackingUp) {
      _backupPending = true;
      return false;
    }

    _isBackingUp = true;
    var success = false;
    try {
      final files = {
        favoritesFileName: favoritesJson ?? await _readFavoritesJson(),
        blackHostFiltersFileName: _hostFiltersJson(HostFilter.blacklist),
        whiteHostFiltersFileName: _hostFiltersJson(HostFilter.whitelist),
      };

      if (AutoBackupStorage.isSafDirectory(backupDirectory)) {
        success = await AutoBackupStorage.writeFiles(backupDirectory, files);
        if (!success) {
          throw Exception('SAF auto backup failed');
        }
        return true;
      }

      final directory = Directory(backupDirectory);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      for (final entry in files.entries) {
        final file = File('${directory.path}${Platform.pathSeparator}${entry.key}');
        await _overwriteFile(file, entry.value);
      }
      success = true;
    } catch (_) {
      await _clearInvalidBackupDirectory();
    } finally {
      _isBackingUp = false;
      if (_backupPending) {
        _backupPending = false;
        success = await backupAll() || success;
      }
    }
    return success;
  }

  static Future<void> _clearInvalidBackupDirectory() async {
    final configuration = AppConfiguration.current;
    if (configuration == null || configuration.autoBackupDirectory == null) {
      return;
    }

    configuration.autoBackupDirectory = null;
    configuration.autoBackupPrompted = false;
    await configuration.flushConfig();
    _backupDirectoryInvalidController.add(null);
  }

  static Future<String> _readFavoritesJson() async {
    final file = await Paths.getPath('favorites.json');
    if (!await file.exists()) {
      return '[]';
    }

    final content = await file.readAsString();
    return content.trim().isEmpty ? '[]' : content;
  }

  static String _hostFiltersJson(HostList hostList) {
    return jsonEncode(hostList.list.map((rule) => rule.pattern.replaceAll('.*', '*')).toList());
  }

  static Future<void> _overwriteFile(File file, String content) async {
    if (await file.exists()) {
      await file.delete();
    }
    await file.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }
}
