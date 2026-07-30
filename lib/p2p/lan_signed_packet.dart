import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/public_key_codec.dart';

abstract final class LanSignedPacket {
  static final _ed = Ed25519();

  static Future<Uint8List> encodeAndSign({
    required Map<String, dynamic> inner,
    required SimpleKeyPair signer,
  }) async {
    final canonical = jsonEncode(inner);
    final body = utf8.encode(canonical);
    final sig = await _ed.sign(body, keyPair: signer);
    final pk = await signer.extractPublicKey();
    final env = <String, dynamic>{
      'v': 1,
      'b64': base64Encode(body),
      'pk': ed25519PublicKeyToHex(pk),
      'sig': sig.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    };
    return utf8.encode(jsonEncode(env));
  }

  static Future<({Map<String, dynamic> inner, SimplePublicKey pk})?> verifyAndDecodeWithKey(Uint8List raw) async {
    try {
      final env = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      if (env['v'] != 1) return null;
      final b64 = env['b64'] as String?;
      final pkHex = env['pk'] as String?;
      final sigHex = env['sig'] as String?;
      if (b64 == null || pkHex == null || sigHex == null) return null;
      final body = base64Decode(b64);
      final pk = parseEd25519PublicKeyHex(pkHex);
      if (pk == null) return null;
      if (sigHex.length != 128) return null;
      final sigBytes = <int>[];
      for (var i = 0; i < 128; i += 2) {
        sigBytes.add(int.parse(sigHex.substring(i, i + 2), radix: 16));
      }
      final sig = Signature(sigBytes, publicKey: pk);
      final ok = await _ed.verify(body, signature: sig);
      if (!ok) return null;
      final inner = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      final ts = inner['ts'];
      if (ts is int) {
        final skew = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)).inSeconds.abs();
        if (skew > 45) return null;
      }
      return (inner: inner, pk: pk);
    } catch (_) {
      return null;
    }
  }
}
