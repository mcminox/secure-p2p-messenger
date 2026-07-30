import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class RotatingPeerId {
  RotatingPeerId({
    required this.window,
    this.salt = '',
  });

  final Duration window;

  final String salt;

  static const deterministicPepper = 'dart_aut|rot_display_v1';

  Uint8List? _edPub;
  Uint8List? _xPub;

  int _lastBucket = -1;
  String _current = '';

  static final _sha = Sha256();

  void updatePublicKeys({
    required Uint8List ed25519Public,
    required Uint8List x25519Public,
  }) {
    _edPub = ed25519Public;
    _xPub = x25519Public;
  }

  Future<String> current() async {
    if (_edPub == null || _xPub == null) {
      return '—';
    }
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ window.inMilliseconds;
    if (bucket == _lastBucket && _current.isNotEmpty) {
      return _current;
    }
    _lastBucket = bucket;
    _current = await computeShortCode(
      ed25519Public: _edPub!,
      x25519Public: _xPub!,
      bucket: bucket,
      salt: salt,
    );
    return _current;
  }

  static Future<String> computeShortCode({
    required Uint8List ed25519Public,
    required Uint8List x25519Public,
    required int bucket,
    String salt = '',
  }) async {
    final mix = salt.isEmpty ? deterministicPepper : '$deterministicPepper|$salt';
    final input = utf8.encode(
      '${base64Encode(ed25519Public)}|${base64Encode(x25519Public)}|$bucket|$mix',
    );
    final hash = await _sha.hash(input);
    return base64Url.encode(hash.bytes.sublist(0, 12)).replaceAll('=', '');
  }

  static Future<bool> publicCodesMatchNow({
    required Uint8List ed25519Public,
    required Uint8List x25519Public,
    required String theyShow,
    Duration window = const Duration(minutes: 15),
    String salt = '',
  }) async {
    final b = DateTime.now().millisecondsSinceEpoch ~/ window.inMilliseconds;
    final a = await computeShortCode(
      ed25519Public: ed25519Public,
      x25519Public: x25519Public,
      bucket: b,
      salt: salt,
    );
    if (a == theyShow) return true;
    final prev = await computeShortCode(
      ed25519Public: ed25519Public,
      x25519Public: x25519Public,
      bucket: b - 1,
      salt: salt,
    );
    return prev == theyShow;
  }

  static Duration defaultWindow() => const Duration(minutes: 15);
}
