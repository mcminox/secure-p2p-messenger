import 'dart:convert';
import 'dart:typed_data';

class JsonFragBuffer {
  JsonFragBuffer(this.n);
  final int n;
  final Map<int, String> chunks = {};

  bool add(int i, String b64) {
    chunks[i] = b64;
    return chunks.length == n;
  }

  String? assembleUtf8() {
    if (chunks.length != n) return null;
    final b = BytesBuilder();
    for (var i = 0; i < n; i++) {
      final c = chunks[i];
      if (c == null) return null;
      b.add(base64Decode(c));
    }
    return utf8.decode(b.toBytes());
  }
}
