import 'dart:convert';

class JsonUrlCodecResult {
  final String text;
  final Set<String> paths;

  const JsonUrlCodecResult(this.text, this.paths);

  bool get changed => paths.isNotEmpty;
}

class JsonUrlCodec {
  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

  static JsonUrlCodecResult decodeStringValues(String text) {
    final decodedPaths = <String>{};
    final object = jsonDecode(text);
    final decoded = _walkDecode(object, '', decodedPaths);
    return JsonUrlCodecResult(_prettyJson.convert(decoded), decodedPaths);
  }

  static String encodeStringValues(String text, Set<String> paths) {
    if (paths.isEmpty) return text;
    final object = jsonDecode(text);
    final encoded = _walkEncode(object, '', paths);
    return _prettyJson.convert(encoded);
  }

  static String encodeAllStringValues(String text) {
    final object = jsonDecode(text);
    final encoded = _walkEncodeAll(object);
    return _prettyJson.convert(encoded);
  }

  static dynamic _walkDecode(dynamic value, String path, Set<String> decodedPaths) {
    if (value is Map) {
      return value.map((key, item) {
        final childPath = '$path/${_escapePath(key.toString())}';
        return MapEntry(key, _walkDecode(item, childPath, decodedPaths));
      });
    }
    if (value is List) {
      return [
        for (var index = 0; index < value.length; index++) _walkDecode(value[index], '$path/$index', decodedPaths)
      ];
    }
    if (value is String && _looksUrlEncoded(value)) {
      try {
        final decoded = Uri.decodeComponent(value);
        if (decoded != value) {
          decodedPaths.add(path);
          return decoded;
        }
      } catch (_) {}
    }
    return value;
  }

  static dynamic _walkEncode(dynamic value, String path, Set<String> paths) {
    if (value is Map) {
      return value.map((key, item) {
        final childPath = '$path/${_escapePath(key.toString())}';
        return MapEntry(key, _walkEncode(item, childPath, paths));
      });
    }
    if (value is List) {
      return [for (var index = 0; index < value.length; index++) _walkEncode(value[index], '$path/$index', paths)];
    }
    if (value is String && paths.contains(path)) {
      return _encodeIfNeeded(value);
    }
    return value;
  }

  static dynamic _walkEncodeAll(dynamic value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key, _walkEncodeAll(item)));
    }
    if (value is List) {
      return value.map(_walkEncodeAll).toList();
    }
    if (value is String) {
      return _encodeIfNeeded(value);
    }
    return value;
  }

  static String _encodeIfNeeded(String value) {
    if (_looksUrlEncoded(value)) {
      try {
        if (Uri.decodeComponent(value) != value) return value;
      } catch (_) {}
    }
    return Uri.encodeComponent(value);
  }

  static bool _looksUrlEncoded(String value) {
    return RegExp(r'%[0-9a-fA-F]{2}').hasMatch(value);
  }

  static String _escapePath(String value) => value.replaceAll('~', '~0').replaceAll('/', '~1');
}
