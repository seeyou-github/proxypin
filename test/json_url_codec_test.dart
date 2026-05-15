import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/json_url_codec.dart';

void main() {
  test('compacts pretty json for sending', () {
    const pretty = '''
{
  "v": "1.0.1",
  "score": "1"
}''';

    expect(JsonUrlCodec.compact(pretty), '{"v":"1.0.1","score":"1"}');
  });

  test('re-encodes decoded json values before compacting', () {
    const decoded = '''
{
  "payload": {
    "name": "Proxy Pin"
  }
}''';

    final encoded = JsonUrlCodec.encodeStringValues(decoded, {'/payload'});

    expect(JsonUrlCodec.compact(encoded), '{"payload":"%7B%22name%22%3A%22Proxy%20Pin%22%7D"}');
  });
}
