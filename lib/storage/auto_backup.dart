import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/native/auto_backup_storage.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/auto_backup_log.dart';
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

  static Future<bool> backupAll({String? favoritesJson, String reason = 'unknown'}) async {
    final backupDirectory = AppConfiguration.current?.autoBackupDirectory;
    await AutoBackupLog.info('Auto backup requested', {
      'reason': reason,
      'hasConfiguredDirectory': backupDirectory?.trim().isNotEmpty == true,
      if (backupDirectory != null) 'backupDirectory': backupDirectory,
      'isBackingUp': _isBackingUp,
      'backupPending': _backupPending,
      'favoritesJsonProvided': favoritesJson != null,
    });

    if (backupDirectory == null || backupDirectory.trim().isEmpty) {
      await AutoBackupLog.warn('Auto backup skipped because directory is not configured', {'reason': reason});
      return false;
    }

    if (_isBackingUp) {
      _backupPending = true;
      await AutoBackupLog.warn('Auto backup deferred because another backup is running', {
        'reason': reason,
        'backupDirectory': backupDirectory,
      });
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
      await AutoBackupLog.info('Auto backup payload prepared', {
        'reason': reason,
        'backupDirectory': backupDirectory,
        'fileNames': files.keys.toList(),
        'fileSizes': files.map((key, value) => MapEntry(key, value.length)),
        'blackHostCount': HostFilter.blacklist.list.length,
        'whiteHostCount': HostFilter.whitelist.list.length,
      });

      if (AutoBackupStorage.isSafDirectory(backupDirectory)) {
        await AutoBackupLog.info('Auto backup uses Android SAF writer', {
          'reason': reason,
          'backupDirectory': backupDirectory,
        });
        success = await AutoBackupStorage.writeFiles(backupDirectory, files);
        if (!success) {
          throw Exception('SAF auto backup failed');
        }
        await AutoBackupLog.info('Auto backup completed with Android SAF writer', {
          'reason': reason,
          'backupDirectory': backupDirectory,
        });
        return true;
      }

      final directory = Directory(backupDirectory);
      await AutoBackupLog.info('Auto backup uses file system writer', {
        'reason': reason,
        'backupDirectory': backupDirectory,
        'directoryExists': await directory.exists(),
      });
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        await AutoBackupLog.info('Auto backup directory created', {
          'reason': reason,
          'backupDirectory': backupDirectory,
        });
      }

      for (final entry in files.entries) {
        final file = File('${directory.path}${Platform.pathSeparator}${entry.key}');
        await AutoBackupLog.info('Auto backup file write started', {
          'reason': reason,
          'filePath': file.path,
          'bytes': entry.value.length,
        });
        await _overwriteFile(file, entry.value);
        await AutoBackupLog.info('Auto backup file write finished', {
          'reason': reason,
          'filePath': file.path,
        });
      }
      success = true;
      await AutoBackupLog.info('Auto backup completed with file system writer', {
        'reason': reason,
        'backupDirectory': backupDirectory,
      });
    } catch (e, t) {
      logger.e('auto backup failed', error: e, stackTrace: t);
      await AutoBackupLog.error('Auto backup failed', e, t, {
        'reason': reason,
        'backupDirectory': backupDirectory,
      });
      await _clearInvalidBackupDirectory();
    } finally {
      _isBackingUp = false;
      if (_backupPending) {
        _backupPending = false;
        await AutoBackupLog.info('Auto backup pending request will run now', {'previousReason': reason});
        success = await backupAll(reason: 'pending-after-$reason') || success;
      }
    }
    await AutoBackupLog.info('Auto backup request finished', {
      'reason': reason,
      'success': success,
    });
    return success;
  }

  static Future<void> _clearInvalidBackupDirectory() async {
    final configuration = AppConfiguration.current;
    if (configuration == null || configuration.autoBackupDirectory == null) {
      await AutoBackupLog.warn('Invalid backup directory cleanup skipped', {
        'hasConfiguration': configuration != null,
      });
      return;
    }

    final invalidDirectory = configuration.autoBackupDirectory;
    await AutoBackupLog.warn('Invalid backup directory will be cleared', {
      'backupDirectory': invalidDirectory,
    });
    configuration.autoBackupDirectory = null;
    configuration.autoBackupPrompted = false;
    await configuration.flushConfig();
    await AutoBackupLog.info('Invalid backup directory cleared and prompt event emitted', {
      'backupDirectory': invalidDirectory,
    });
    _backupDirectoryInvalidController.add(null);
  }

  static Future<String> _readFavoritesJson() async {
    final file = await Paths.getPath('favorites.json');
    if (!await file.exists()) {
      await AutoBackupLog.warn('Favorites source file does not exist, backing up empty list', {'path': file.path});
      return '[]';
    }

    final content = await file.readAsString();
    final normalized = content.trim().isEmpty ? '[]' : content;
    await AutoBackupLog.info('Favorites source file read', {
      'path': file.path,
      'bytes': content.length,
      'normalizedBytes': normalized.length,
    });
    return normalized;
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
