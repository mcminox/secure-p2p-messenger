import 'dart:io' show Platform;

bool get inviteScannerSupported => Platform.isAndroid || Platform.isIOS;
