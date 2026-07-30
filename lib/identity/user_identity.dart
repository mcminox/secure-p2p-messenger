import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class UserIdentity {
  UserIdentity({
    required this.ed25519,
    required this.x25519Static,
  });

  final SimpleKeyPair ed25519;
  final SimpleKeyPair x25519Static;

  static final _ed = Ed25519();
  static final _x = X25519();

  static Future<UserIdentity> createFreshKeyMaterial() async {
    final ed = await _ed.newKeyPair();
    final xs = await _x.newKeyPair();
    return UserIdentity(ed25519: ed, x25519Static: xs);
  }

  static Future<UserIdentity> fromSeeds(Uint8List edSeed, Uint8List xSeed) async {
    final ed = await _ed.newKeyPairFromSeed(edSeed);
    final xs = await _x.newKeyPairFromSeed(xSeed);
    return UserIdentity(ed25519: ed, x25519Static: xs);
  }

  Future<SimplePublicKey> ed25519PublicKey() => ed25519.extractPublicKey();

  Future<SimplePublicKey> x25519PublicKey() => x25519Static.extractPublicKey();

  static Uint8List randomSalt16() {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
  }
}
