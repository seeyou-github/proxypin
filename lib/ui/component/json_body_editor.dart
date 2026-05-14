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

  @override
  void initState() {
    super.initState();
    final text = widget.text ?? '';
    _jsonMode = _isJson(text);
    _codeController = CodeController(language: highlight_json.json, text: text);
    _codeController.addListener(_onCodeChanged);
    _textController = TextEditingController(text: text);
  }

  @override
  void didUpdateWidget(covariant JsonBodyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text) return;

    final text = widget.text ?? '';
    _jsonMode = _isJson(text);
    _updatingFromWidget = true;
    _codeController.text = text;
    _updatingFromWidget = false;
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
    widget.onChanged?.call(_codeController.text);
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

  void _formatJson() {
    final localizations = AppLocalizations.of(context)!;
    try {
      final formatted = const JsonEncoder.withIndent('  ').convert(jsonDecode(_codeController.text));
      _codeController.text = formatted;
    } catch (_) {
      FlutterToastr.show(localizations.fail, context);
    }
  }

  void _urlDecodeJsonValues() {
    final localizations = AppLocalizations.of(context)!;
    try {
      final result = JsonUrlCodec.decodeStringValues(_codeController.text);
      _codeController.text = result.text;
      widget.onUrlDecodedPathsChanged?.call(result.paths);
    } catch (_) {
      FlutterToastr.show(localizations.decodeFail, context);
    }
  }

  void _urlEncodeJsonValues() {
    final localizations = AppLocalizations.of(context)!;
    try {
      final result = JsonUrlCodec.encodeAllStringValues(_codeController.text);
      _codeController.text = result;
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
                visualDensity: VisualDensity.compact,
                onPressed: _urlDecodeJsonValues,
                child: Text(localizations.urlDecode),
              ),
              TextButton(
                visualDensity: VisualDensity.compact,
                onPressed: _urlEncodeJsonValues,
                child: Text(localizations.urlEncode),
              ),
              TextButton(
                visualDensity: VisualDensity.compact,
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
