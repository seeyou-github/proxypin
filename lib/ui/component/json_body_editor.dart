import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:highlight/languages/json.dart' as highlight_json;
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/json_url_codec.dart';
import 'package:proxypin/utils/platform.dart';

class JsonBodyEditor extends StatefulWidget {
  final String? text;
  final ValueChanged<String>? onChanged;
  final ValueChanged<Set<String>>? onUrlDecodedPathsChanged;
  final int minLines;
  final int? maxLines;
  final bool autofocus;

  const JsonBodyEditor({
    super.key,
    this.text,
    this.onChanged,
    this.onUrlDecodedPathsChanged,
    this.minLines = 3,
    this.maxLines,
    this.autofocus = false,
  });

  @override
  State<JsonBodyEditor> createState() => _JsonBodyEditorState();
}

class _JsonBodyEditorState extends State<JsonBodyEditor> {
  late CodeController _codeController;
  late TextEditingController _textController;
  late bool _jsonMode;
  bool _updatingFromWidget = false;
  String? _lastEmittedText;
  Set<String> _urlDecodedPaths = {};

  @override
  void initState() {
    super.initState();
    final text = widget.text ?? '';
    _jsonMode = _isJson(text);
    final initialText = _jsonMode ? _prettyJson(text) : text;
    _codeController = CodeController(language: highlight_json.json, text: initialText);
    _codeController.addListener(_onCodeChanged);
    _textController = TextEditingController(text: text);
    if (initialText != text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emitChanged(initialText));
    }
  }

  @override
  void didUpdateWidget(covariant JsonBodyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text || widget.text == _codeController.text || widget.text == _lastEmittedText) {
      return;
    }

    final text = widget.text ?? '';
    _jsonMode = _isJson(text);
    _urlDecodedPaths = {};
    _setCodeText(_jsonMode ? _prettyJson(text) : text, notify: false);
    _textController.text = text;
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    if (_updatingFromWidget) return;
    _emitChanged(_codeController.text);
  }

  void _emitChanged(String text) {
    _lastEmittedText = text;
    widget.onChanged?.call(text);
  }

  void _setCodeText(String text, {bool notify = true}) {
    _updatingFromWidget = !notify;
    _codeController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _updatingFromWidget = false;
    if (notify) {
      _emitChanged(text);
    }
  }

  bool _isJson(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    if (!(value.startsWith('{') && value.endsWith('}')) && !(value.startsWith('[') && value.endsWith(']'))) {
      return false;
    }

    try {
      jsonDecode(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _prettyJson(String text) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } catch (_) {
      return text;
    }
  }

  void _formatJson() {
    final localizations = AppLocalizations.of(context)!;
    try {
      _setCodeText(_prettyJson(_codeController.text));
    } catch (_) {
      FlutterToastr.show(localizations.fail, context);
    }
  }

  void _urlDecodeJsonValues() {
    final localizations = AppLocalizations.of(context)!;
    try {
      final result = JsonUrlCodec.decodeStringValues(_codeController.text);
      _urlDecodedPaths = result.paths;
      _setCodeText(result.text);
      widget.onUrlDecodedPathsChanged?.call(_urlDecodedPaths);
    } catch (_) {
      FlutterToastr.show(localizations.decodeFail, context);
    }
  }

  void _urlEncodeJsonValues() {
    final localizations = AppLocalizations.of(context)!;
    try {
      final result = _urlDecodedPaths.isEmpty
          ? JsonUrlCodec.encodeAllStringValues(_codeController.text)
          : JsonUrlCodec.encodeStringValues(_codeController.text, _urlDecodedPaths);
      _urlDecodedPaths = {};
      _setCodeText(result);
      widget.onUrlDecodedPathsChanged?.call({});
    } catch (_) {
      FlutterToastr.show(localizations.encodeFail, context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    if (!_jsonMode) {
      return TextField(
        autofocus: widget.autofocus,
        controller: _textController,
        onChanged: widget.onChanged,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
      );
    }

    final lines = widget.maxLines ?? widget.minLines;
    final height = (lines * 22.0) + 72.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 2,
            children: [
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: _urlDecodeJsonValues,
                child: Text(localizations.urlDecode),
              ),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: _urlEncodeJsonValues,
                child: Text(localizations.urlEncode),
              ),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: _formatJson,
                child: Text(localizations.jsonFormat),
              ),
            ],
          ),
        ),
        SizedBox(
          height: height.clamp(140.0, 460.0).toDouble(),
          child: CodeTheme(
            data: CodeThemeData(
              styles: Theme.brightnessOf(context) == Brightness.light ? atomOneLightTheme : atomOneDarkTheme,
            ),
            child: CodeField(
              background: Colors.transparent,
              controller: _codeController,
              wrap: true,
              readOnly: false,
              gutterStyle: GutterStyle(
                margin: 0,
                width: Platforms.isMobile() ? 36 : 48,
                showErrors: false,
              ),
              textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.35),
            ),
          ),
        ),
      ],
    );
  }
}
