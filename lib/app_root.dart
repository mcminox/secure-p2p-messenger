import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth/secure_app_repository.dart';
import 'identity/user_identity.dart';
import 'prefs/app_preferences.dart';
import 'security/security_audit_log.dart';
import 'security/license_guard.dart';
import 'ui/app_theme.dart';
import 'ui/auth/lock_page.dart';
import 'ui/auth/panic_mode_page.dart';
import 'ui/auth/set_password_page.dart';
import 'ui/messenger_home_page.dart';
import 'ui/safety_loading_screen.dart';

enum _AppPhase { loading, setup, lock, home, panic }

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  final _repo = SecureAppRepository();
  final _prefs = AppPreferences();
  final _license = LicenseGuard();
  static const _lockCooldown = Duration(minutes: 5);
  _AppPhase _phase = _AppPhase.loading;
  UserIdentity? _identity;
  DateTime? _backgroundAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_phase != _AppPhase.home) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _backgroundAt ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final at = _backgroundAt;
      _backgroundAt = null;
      if (at == null) return;
      if (DateTime.now().difference(at) >= _lockCooldown) {
        _lockSession();
      }
    }
  }

  Future<void> _bootstrap() async {
    final panic = await _prefs.isPanicModeEnabled();
    if (panic) {
      if (!mounted) return;
      setState(() => _phase = _AppPhase.panic);
      return;
    }
    final configured = await _repo.isPasswordConfigured;
    if (!mounted) return;
    setState(() {
      _phase = configured ? _AppPhase.lock : _AppPhase.setup;
    });
  }

  void _lockSession() {
    _backgroundAt = null;
    _repo.clearSession();
    setState(() {
      _identity = null;
      if (_phase == _AppPhase.home) {
        _phase = _AppPhase.lock;
      }
    });
  }

  Future<bool> _assertLicenseOrLock() async {
    final ok = await _license.canAccessSecureFlows();
    if (ok) return true;
    await SecurityAuditLog.instance.append('license_check_failed_or_blocked');
    _lockSession();
    return false;
  }

  Future<void> _wipeAndRestart() async {
    await _repo.wipeEverything();
    if (!mounted) return;
    setState(() {
      _identity = null;
      _phase = _AppPhase.setup;
    });
  }

  Future<void> _panicWipeAndExit() async {
    await SecurityAuditLog.instance.append('panic_wipe_requested');
    await _prefs.setPanicModeEnabled(true);
    await _repo.wipeEverything();
    if (!mounted) return;
    setState(() {
      _identity = null;
      _phase = _AppPhase.panic;
    });
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart AUT',
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) {
          switch (_phase) {
            case _AppPhase.loading:
              return const SafetyLoadingScreen(message: 'Инициализация…');
            case _AppPhase.setup:
              return SetPasswordPage(
                repository: _repo,
                onCompleted: (identity) {
                  _assertLicenseOrLock().then((ok) {
                    if (!ok || !mounted) return;
                    setState(() {
                      _identity = identity;
                      _phase = _AppPhase.home;
                    });
                  });
                },
              );
            case _AppPhase.lock:
              return LockPage(
                repository: _repo,
                onPanicRequested: _panicWipeAndExit,
                onUnlocked: (id) {
                  _assertLicenseOrLock().then((ok) {
                    if (!ok || !mounted) return;
                    setState(() {
                      _identity = id;
                      _phase = _AppPhase.home;
                    });
                  });
                },
              );
            case _AppPhase.home:
              final id = _identity;
              if (id == null) {
                return LockPage(
                  repository: _repo,
                  onPanicRequested: _panicWipeAndExit,
                  onUnlocked: (i) {
                    _assertLicenseOrLock().then((ok) {
                      if (!ok || !mounted) return;
                      setState(() {
                        _identity = i;
                        _phase = _AppPhase.home;
                      });
                    });
                  },
                );
              }
              return MessengerHomePage(
                identity: id,
                repository: _repo,
                onLock: _lockSession,
                onPanicLock: _panicWipeAndExit,
                onWipeAllData: _wipeAndRestart,
              );
            case _AppPhase.panic:
              return const PanicModePage();
          }
        },
      ),
    );
  }
}
