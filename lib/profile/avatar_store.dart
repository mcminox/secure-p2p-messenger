import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

class AvatarStore {
  AvatarStore._();
  static final AvatarStore instance = AvatarStore._();

  Future<Directory> _profileDir() async {
    final root = await getApplicationSupportDirectory();
    final d = Directory('${root.path}/profile');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _myAvatarFile() async {
    final d = await _profileDir();
    return File('${d.path}/me_avatar.png');
  }

  Future<Directory> _peersDir() async {
    final d = Directory('${(await _profileDir()).path}/peers');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _peerAvatarFile(String fingerprint) async {
    final d = await _peersDir();
    final safe = fingerprint.replaceAll(RegExp(r'[^a-zA-Z0-9:_-]'), '_');
    return File('${d.path}/$safe.png');
  }

  Future<Uint8List> _resizeToPng(Uint8List src, {int maxSide = 256}) async {
    final codec = await ui.instantiateImageCodec(src);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width;
    final h = img.height;
    final scale = w > h ? maxSide / w : maxSide / h;
    final tw = scale < 1 ? (w * scale).round() : w;
    final th = scale < 1 ? (h * scale).round() : h;
    final resizedCodec = await ui.instantiateImageCodec(src, targetWidth: tw, targetHeight: th);
    final resizedFrame = await resizedCodec.getNextFrame();
    final bd = await resizedFrame.image.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) throw StateError('avatar encode failed');
    return bd.buffer.asUint8List();
  }

  Future<void> setMyAvatarFromBytes(Uint8List bytes) async {
    final png = await _resizeToPng(bytes);
    final f = await _myAvatarFile();
    await f.writeAsBytes(png, flush: true);
  }

  Future<String?> myAvatarPathOrNull() async {
    final f = await _myAvatarFile();
    if (!await f.exists()) return null;
    return f.path;
  }

  Future<void> clearMyAvatar() async {
    final f = await _myAvatarFile();
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<String?> myAvatarB64OrNull() async {
    final f = await _myAvatarFile();
    if (!await f.exists()) return null;
    final b = await f.readAsBytes();
    if (b.isEmpty) return null;
    return base64Encode(b);
  }

  Future<void> savePeerAvatarB64(String peerFingerprint, String avatarB64) async {
    try {
      final raw = base64Decode(avatarB64);
      final png = await _resizeToPng(raw);
      final f = await _peerAvatarFile(peerFingerprint);
      await f.writeAsBytes(png, flush: true);
    } catch (_) {}
  }

  Future<String?> peerAvatarPathOrNull(String peerFingerprint) async {
    final f = await _peerAvatarFile(peerFingerprint);
    if (!await f.exists()) return null;
    return f.path;
  }
}
