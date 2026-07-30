import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';


SimplePublicKey? parseEd25519PublicKeyHex(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(s)) return null;
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return SimplePublicKey(bytes, type: KeyPairType.ed25519);
}

String ed25519PublicKeyToHex(SimplePublicKey pk) {
  return pk.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

bool ed25519PublicKeysEqual(SimplePublicKey a, SimplePublicKey b) {
  final x = a.bytes;
  final y = b.bytes;
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

SimplePublicKey? parseX25519PublicKeyHex(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final s = raw.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(s)) return null;
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return SimplePublicKey(bytes, type: KeyPairType.x25519);
}

String x25519PublicKeyToHex(SimplePublicKey pk) {
  return pk.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
