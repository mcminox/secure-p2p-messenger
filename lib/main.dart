import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'app_root.dart';
import 'prefs/app_preferences.dart';
import 'util/local_notifications.dart';
import 'util/mx_provenance.dart';
import 'util/webrtc_deeplink_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    debugPrint('provenance ${MxProvenance.mark} by ${MxProvenance.owner}');
    return true;
  }());
  final prefs = AppPreferences();
  final deviceId = await prefs.deviceId();
  if (deviceId == null || deviceId.isEmpty) {
    await prefs.setDeviceId(const Uuid().v4());
  }
  final buildFp = await prefs.appBuildFingerprint();
  if (buildFp == null || buildFp.isEmpty) {
    await prefs.setAppBuildFingerprint(MxProvenance.mark);
  }
  await WebrtcDeepLinkBridge.instance.initialize();
  await LocalNotifications.instance.initialize();
  runApp(const AppRoot());
}
