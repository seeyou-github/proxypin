import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/json_url_codec.dart';

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
  late TextEditingController _textController;
  late bool _jsonMode;
  String? _lastEmittedText;
  Set<String> _urlDecodedPaths = {};

  @override
  void initState() {
    super.initState();
    final text = widget.text ?? '';
    _jsonMode = _isJson(text);
    final initialText = _jsonMode ? _prettyJson(text) : text;
    _textController = TextEditingController(text: initialText);
    if (initialText != text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emitChanged(initialText));
    }
  }

  @override
  void didUpdateWidget(covariant JsonBodyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text || widget.text == _textController.text || widget.text == _lastEmittedText) {
      return;
    }

    final text = widget.text ?? '';
    _jsonMode = _isJson(text);
    _urlDecodedPaths = {};
    _setText(_jsonMode ? _prettyJson(text) : text, notify: false);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _emitChanged(String text) {
    _lastEmittedText = text;
    widget.onChanged?.call(text);
  }

  void _setText(String text, {bool notify = true}) {
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
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
      _setText(_prettyJson(_textController.text));
    } catch (_) {
      FlutterToastr.show(localizations.fail, context);
    }
  }

  void _urlDecodeJsonValues() {
    final localizations = AppLocalizations.of(context)!;
    try {
      final result = JsonUrlCodec.decodeStringValues(_textController.text);
      _urlDecodedPaths = result.paths;
      _setText(result.text);
      widget.onUrlDecodedPathsChanged?.call(_urlDecodedPaths);
    } catch (_) {
      FlutterToastr.show(localizations.decodeFail, context);
    }
  }

  void _urlEncodeJsonValues() {
    final localizations = AppLocalizations.of(context)!;
    try {
      final result = _urlDecodedPaths.isEmpty
          ? JsonUrlCodec.encodeAllStringValues(_textController.text)
          : JsonUrlCodec.encodeStringValues(_textController.text, _urlDecodedPaths);
      _urlDecodedPaths = {};
      _setText(result);
      widget.onUrlDecodedPathsChanged?.call({});
    } catch (_) {
      FlutterToastr.show(localizations.encodeFail, context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final lines = widget.maxLines ?? widget.minLines;
    final height = (lines * 22.0) + 72.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_jsonMode)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 2,
              children: [
                TextButton(
                  onPressed: _urlDecodeJsonValues,
                  child: Text(localizations.urlDecode),
                ),
                TextButton(
                  onPressed: _urlEncodeJsonValues,
                  child: Text(localizations.urlEncode),
                ),
                TextButton(
                  onPressed: _formatJson,
                  child: Text(localizations.jsonFormat),
                ),
              ],
            ),
          ),
        SizedBox(
          height: height.clamp(140.0, 460.0).toDouble(),
          child: TextField(
            autofocus: widget.autofocus,
            controller: _textController,
            onChanged: _emitChanged,
            expands: true,
            minLines: null,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.35),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}
