import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'public_key_codec.dart';

abstract final class ConversationCrypto {
  static final _x = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aead = Chacha20.poly1305Aead();
  static final _rng = Random.secure();

  static Future<SecretKey> directSharedMessageKey({
    required SimpleKeyPair myX25519,
    required SimplePublicKey peerX25519Public,
    required String conversationId,
  }) async {
    final shared = await _x.sharedSecretKey(
      keyPair: myX25519,
      remotePublicKey: peerX25519Public,
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: Uint8List(0),
      info: Uint8List.fromList(utf8.encode('spm-direct-msg|$conversationId')),
    );
  }

  static SecretKey randomGroupMessageKey() {
    final b = Uint8List(32);
    for (var i = 0; i < b.length; i++) {
      b[i] = _rng.nextInt(256);
    }
    return SecretKey(b);
  }

  static Future<Map<String, dynamic>> wrapGroupKeyForRecipient({
    required SecretKey groupKey,
    required SimpleKeyPair senderX25519,
    required SimplePublicKey senderX25519Public,
    required SimplePublicKey recipientX25519Public,
    required String conversationId,
    required String senderFingerprint,
    required String recipientFingerprint,
  }) async {
    final shared = await _x.sharedSecretKey(
      keyPair: senderX25519,
      remotePublicKey: recipientX25519Public,
    );
    final wrapKey = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: Uint8List(0),
      info: Uint8List.fromList(
        utf8.encode('spm-group-wrap|$conversationId|$senderFingerprint|$recipientFingerprint'),
      ),
    );
    final raw = await groupKey.extractBytes();
    final box = await _aead.encrypt(raw, secretKey: wrapKey);
    return {
      'v': 1,
      'sender_x25519_pub_hex': x25519PublicKeyToHex(senderX25519Public),
      'recipient_fp': recipientFingerprint,
      'ct_b64': base64Encode(box.cipherText),
      'mac_b64': base64Encode(box.mac.bytes),
      'nonce_b64': base64Encode(box.nonce),
    };
  }

  static Future<SecretKey> unwrapGroupKeyFromEnvelope({
    required Map<String, dynamic> envelope,
    required SimpleKeyPair recipientX25519,
    required String conversationId,
    required String senderFingerprint,
    required String recipientFingerprint,
  }) async {
    if ((envelope['v'] as num?)?.toInt() != 1) {
      throw StateError('Unsupported group key envelope version');
    }
    final senderHex = envelope['sender_x25519_pub_hex'] as String?;
    final senderXPub = parseX25519PublicKeyHex(senderHex);
    if (senderXPub == null) throw StateError('Invalid sender X25519 in envelope');
    final shared = await _x.sharedSecretKey(
      keyPair: recipientX25519,
      remotePublicKey: senderXPub,
    );
    final wrapKey = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: Uint8List(0),
      info: Uint8List.fromList(
        utf8.encode('spm-group-wrap|$conversationId|$senderFingerprint|$recipientFingerprint'),
      ),
    );
    final box = SecretBox(
      base64Decode(envelope['ct_b64'] as String),
      mac: Mac(base64Decode(envelope['mac_b64'] as String)),
      nonce: base64Decode(envelope['nonce_b64'] as String),
    );
    final raw = await _aead.decrypt(box, secretKey: wrapKey);
    return SecretKey(raw);
  }

  static Future<Map<String, dynamic>> sealMessageBody({
    required SecretKey key,
    required String plaintext,
  }) async {
    final box = await _aead.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return {
      'enc_v1': true,
      'ct_b64': base64Encode(box.cipherText),
      'mac_b64': base64Encode(box.mac.bytes),
      'nonce_b64': base64Encode(box.nonce),
    };
  }

  static Future<String> openMessageBody({
    required SecretKey key,
    required Map<String, dynamic> j,
  }) async {
    final ct = base64Decode(j['ct_b64'] as String);
    final mac = base64Decode(j['mac_b64'] as String);
    final nonce = base64Decode(j['nonce_b64'] as String);
    final clear = await _aead.decrypt(
      SecretBox(ct, mac: Mac(mac), nonce: nonce),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  static Future<String> safetyNumberLines(
    SimplePublicKey myEd,
    SimplePublicKey peerEd,
  ) async {
    final a = ed25519PublicKeyToHex(myEd);
    final b = ed25519PublicKeyToHex(peerEd);
    final first = a.compareTo(b) <= 0 ? a : b;
    final second = a.compareTo(b) <= 0 ? b : a;
    final h = await Sha256().hash(utf8.encode('$first|$second'));
    final digits = StringBuffer();
    for (var i = 0; i < h.bytes.length && digits.length < 60; i++) {
      digits.write(h.bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    final s = digits.toString();
    final parts = <String>[];
    for (var i = 0; i < s.length; i += 5) {
      parts.add(s.substring(i, i + 5 > s.length ? s.length : i + 5));
    }
    return parts.join(' ');
  }
}
