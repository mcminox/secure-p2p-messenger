import 'package:flutter/foundation.dart' show kIsWeb;

import 'scanner_support_stub.dart' if (dart.library.io) 'scanner_support_io.dart' as impl;

bool get inviteScannerSupported => !kIsWeb && impl.inviteScannerSupported;
