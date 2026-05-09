import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/ui/configuration.dart';

class AutoBackup {
  static const favoritesFileName = 'AutoBackup_favorites.json';
  static const blackHostFiltersFileName = 'AutoBackup_host-filters-black.config';
  static const whiteHostFiltersFileName = 'AutoBackup_host-filters-white.config';

  static bool _isBackingUp = false;

  static Future<void> backupAll({String? favoritesJson}) async {
    final backupDirectory = AppConfiguration.current?.autoBackupDirectory;
    if (backupDirectory == null || backupDirectory.trim().isEmpty || _isBackingUp) {
      return;
    }

    _isBackingUp = true;
    try {
      final directory = Directory(backupDirectory);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      await _overwriteFile(File('${directory.path}${Platform.pathSeparator}$favoritesFileName'),
          favoritesJson ?? await _readFavoritesJson());
      await _overwriteFile(File('${directory.path}${Platform.pathSeparator}$blackHostFiltersFileName'),
          _hostFiltersJson(HostFilter.blacklist));
      await _overwriteFile(File('${directory.path}${Platform.pathSeparator}$whiteHostFiltersFileName'),
          _hostFiltersJson(HostFilter.whitelist));
    } catch (e, t) {
      logger.e('auto backup failed', error: e, stackTrace: t);
    } finally {
      _isBackingUp = false;
    }
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
