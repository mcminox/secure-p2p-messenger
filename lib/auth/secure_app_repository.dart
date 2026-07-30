import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../identity/user_identity.dart';
import '../p2p/lan_install_id.dart';

enum AppPasswordKind {
  text,

  pin,
}

class SecureAppRepository {
  SecureAppRepository({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;

  SecretKey? _sessionMessageWrapKey;
  int _failedUnlockAttempts = 0;
  static const int maxUnlockAttemptsPerSession = 5;

  SecretKey? get sessionMessageWrapKey => _sessionMessageWrapKey;
  int get failedUnlockAttempts => _failedUnlockAttempts;
  int get unlockAttemptsLeft => maxUnlockAttemptsPerSession - _failedUnlockAttempts;
  bool get shouldPanicWipe => _failedUnlockAttempts >= maxUnlockAttemptsPerSession;

  void clearSession() {
    _sessionMessageWrapKey = null;
    _failedUnlockAttempts = 0;
  }

  static const _kSalt = 'spm_v1_pwd_salt';
  static const _kVerifier = 'spm_v1_pwd_verifier';
  static const _kEncEd = 'spm_v1_enc_ed_seed';
  static const _kEncX = 'spm_v1_enc_x_seed';
  static const _kConfigured = 'spm_v1_configured';
  static const _kPwdKind = 'spm_v1_pwd_kind';

  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _pbkdfIterations,
    bits: 256,
  );
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aead = Chacha20.poly1305Aead();
  static final _sha = Sha256();

  static const int _pbkdfIterations = 120000;

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  Future<bool> get isPasswordConfigured async {
    final v = await _storage.read(key: _kConfigured);
    return v == '1';
  }

  Future<AppPasswordKind> get storedPasswordKind async {
    if (!await isPasswordConfigured) return AppPasswordKind.text;
    final v = await _storage.read(key: _kPwdKind);
    if (v == 'pin') return AppPasswordKind.pin;
    return AppPasswordKind.text;
  }

  Future<SecretKey> _deriveMasterKey(String password, Uint8List salt) async {
    return _pbkdf2.deriveKey(
      secretKey: SecretKey(_utf8(password)),
      nonce: salt,
    );
  }

  Future<SecretKey> _deriveDataKey(SecretKey masterKey) async {
    return _hkdf.deriveKey(
      secretKey: masterKey,
      nonce: Uint8List(0),
      info: _utf8('secure_p2p_messenger|dek-v1'),
    );
  }

  Future<Uint8List> _verifierFromMaster(SecretKey masterKey) async {
    final raw = await masterKey.extractBytes();
    final h = await _sha.hash([...raw, ..._utf8('|spm-verifier-v1|')]);
    return Uint8List.fromList(h.bytes);
  }

  bool _constTimeEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var x = 0;
    for (var i = 0; i < a.length; i++) {
      x |= a[i] ^ b[i];
    }
    return x == 0;
  }

  Future<Uint8List> _encryptSeed(SecretKey dataKey, List<int> seed) async {
    final box = await _aead.encrypt(seed, secretKey: dataKey);
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes, ...box.nonce]);
  }

  Future<Uint8List> _decryptSeed(SecretKey dataKey, Uint8List wire) async {
    if (wire.length < 12 + 16) throw StateError('truncated');
    final nonce = wire.sublist(wire.length - 12);
    final mac = wire.sublist(wire.length - 28, wire.length - 12);
    final ct = wire.sublist(0, wire.length - 28);
    final clear = await _aead.decrypt(
      SecretBox(ct, mac: Mac(mac), nonce: nonce),
      secretKey: dataKey,
    );
    return Uint8List.fromList(clear);
  }

  Future<void> setupPasswordOnce(String password, AppPasswordKind kind) async {
    if (await isPasswordConfigured) {
      throw StateError('Пароль уже задан на этом устройстве.');
    }
    if (kind == AppPasswordKind.pin) {
      if (!RegExp(r'^\d+$').hasMatch(password)) {
        throw ArgumentError('ПИН должен состоять только из цифр.');
      }
      if (password.length < 6) {
        throw ArgumentError('Минимум 6 цифр.');
      }
    } else {
      if (password.length < 10) {
        throw ArgumentError('Минимум 10 символов.');
      }
    }
    final salt16 = UserIdentity.randomSalt16();

    final mk = await _deriveMasterKey(password, salt16);
    final verifier = await _verifierFromMaster(mk);
    final dek = await _deriveDataKey(mk);

    final id = await UserIdentity.createFreshKeyMaterial();

    final edD = await id.ed25519.extract();
    final xD = await id.x25519Static.extract();

    final e1 = await _encryptSeed(dek, edD.bytes);
    final e2 = await _encryptSeed(dek, xD.bytes);

    await _storage.write(key: _kSalt, value: base64Encode(salt16));
    await _storage.write(key: _kVerifier, value: base64Encode(verifier));
    await _storage.write(key: _kEncEd, value: base64Encode(e1));
    await _storage.write(key: _kEncX, value: base64Encode(e2));
    await _storage.write(key: _kPwdKind, value: kind.name);
    await _storage.write(key: _kConfigured, value: '1');
  }

  Future<UserIdentity?> tryUnlock(String password) async {
    if (!await isPasswordConfigured) return null;
    final saltB64 = await _storage.read(key: _kSalt);
    final verB64 = await _storage.read(key: _kVerifier);
    final eEd = await _storage.read(key: _kEncEd);
    final eX = await _storage.read(key: _kEncX);
    if (saltB64 == null || verB64 == null || eEd == null || eX == null) {
      return null;
    }
    final salt = base64Decode(saltB64);
    final want = base64Decode(verB64);
    final mk = await _deriveMasterKey(password, Uint8List.fromList(salt));
    final got = await _verifierFromMaster(mk);
    if (!_constTimeEq(got, Uint8List.fromList(want))) {
      _failedUnlockAttempts++;
      return null;
    }
    _failedUnlockAttempts = 0;
    final dek = await _deriveDataKey(mk);
    _sessionMessageWrapKey = await _hkdf.deriveKey(
      secretKey: dek,
      nonce: Uint8List(0),
      info: _utf8('secure_p2p|session-msg-wrap-v1'),
    );
    final edClear = await _decryptSeed(dek, base64Decode(eEd));
    final xClear = await _decryptSeed(dek, base64Decode(eX));
    return UserIdentity.fromSeeds(edClear, xClear);
  }

  Future<void> wipeEverything() async {
    clearSession();
    await _storage.deleteAll();
    await LanInstallId.clear();
    try {
      final root = await getApplicationSupportDirectory();
      final chats = Directory('${root.path}/chats');
      if (await chats.exists()) {
        await _bestEffortWipeDirectory(chats);
        await chats.delete(recursive: true);
      }
      await for (final e in root.list()) {
        if (e is Directory && e.path.contains('chats')) {
          try {
            await _bestEffortWipeDirectory(e);
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (e, st) {
      debugPrint('wipe directories: $e\n$st');
    }
    try {
      final doc = await getApplicationDocumentsDirectory();
      final legacy = Directory('${doc.path}/secure_p2p_messenger');
      if (await legacy.exists()) {
        await _bestEffortWipeDirectory(legacy);
        await legacy.delete(recursive: true);
      }
    } catch (_) {}
    try {
      final tmp = await getTemporaryDirectory();
      if (await tmp.exists()) {
        await _bestEffortWipeDirectory(tmp);
        await tmp.delete(recursive: true);
      }
    } catch (_) {}
    try {
      final cache = await getApplicationCacheDirectory();
      if (await cache.exists()) {
        await _bestEffortWipeDirectory(cache);
        await cache.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _bestEffortWipeDirectory(Directory dir) async {
    final rnd = Random.secure();
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      try {
        final len = await e.length();
        if (len <= 0) continue;
        final raf = await e.open(mode: FileMode.write);
        var left = len;
        while (left > 0) {
          final chunkLen = left > 4096 ? 4096 : left;
          final chunk = Uint8List(chunkLen);
          for (var i = 0; i < chunkLen; i++) {
            chunk[i] = rnd.nextInt(256);
          }
          await raf.writeFrom(chunk);
          left -= chunkLen;
        }
        await raf.flush();
        await raf.close();
      } catch (_) {
      }
    }
  }
}
