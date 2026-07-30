import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

abstract final class LanInstallId {
  static const _k = 'dart_aut_lan_install_id';

  static const legacyUnknown = '__legacy__';

  static Future<String> getOrCreate() async {
    final p = await SharedPreferences.getInstance();
    var v = p.getString(_k);
    if (v == null || v.isEmpty) {
      v = const Uuid().v4();
      await p.setString(_k, v);
    }
    return v;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_k);
  }
}
