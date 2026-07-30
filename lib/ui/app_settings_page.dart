import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';

import '../prefs/app_preferences.dart';
import '../security/auth_api_service.dart';
import 'widgets/app_snack.dart';
import 'widgets/messenger_backdrop.dart';
import 'widgets/secure_ui.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({
    super.key,
    required this.prefs,
  });

  final AppPreferences prefs;

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final _serverUrlCtl = TextEditingController();
  final _serverPinCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _mfaCtl = TextEditingController();
  final _authApi = AuthApiService();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadServer();
  }

  @override
  void dispose() {
    _serverUrlCtl.dispose();
    _serverPinCtl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    _mfaCtl.dispose();
    super.dispose();
  }

  Future<void> _loadServer() async {
    final savedBase = await widget.prefs.serverBaseUrl();
    _serverUrlCtl.text = savedBase.isEmpty ? 'https://hm491715.webhm.pro' : savedBase;
    _serverPinCtl.text = await widget.prefs.serverPin();
    if (mounted) setState(() {});
  }

  Future<void> _saveServer() async {
    await widget.prefs.setServerBaseUrl(_serverUrlCtl.text);
    await widget.prefs.setServerPin(_serverPinCtl.text);
    if (mounted) AppSnack.show(context, 'Серверные настройки сохранены');
  }

  Future<String> _hashPassword(String password) async {
    final digest = await Sha256().hash(password.codeUnits);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _loginServer() async {
    setState(() => _busy = true);
    try {
      final did = await widget.prefs.deviceId() ?? '';
      final pwh = await _hashPassword(_passCtl.text);
      final res = await _authApi.login(
        email: _emailCtl.text.trim(),
        passwordHash: pwh,
        deviceId: did,
      );
      final uid = res['user_id']?.toString();
      final access = res['access_token']?.toString();
      final refresh = res['refresh_token']?.toString();
      if (uid != null && access != null && refresh != null) {
        await widget.prefs.setUserId(uid);
        await widget.prefs.setAccessToken(access);
        await widget.prefs.setRefreshToken(refresh);
        final nick = res['nickname']?.toString();
        final token = res['connect_token']?.toString();
        if (nick != null && nick.isNotEmpty) await widget.prefs.setNickname(nick);
        if (token != null && token.isNotEmpty) await widget.prefs.setConnectToken(token);
        final sub = await _authApi.subscription(userId: uid, accessToken: access);
        final status = sub['status']?.toString() ?? 'trial';
        await widget.prefs.setSubscriptionStatus(status);
      }
      if ((res['mfa_required'] == true) && mounted) {
        AppSnack.show(context, 'Нужен 2FA код владельца');
        return;
      }
      if (mounted) AppSnack.show(context, 'Вход выполнен, лицензия будет проверяться сервером');
    } catch (e) {
      if (mounted) AppSnack.show(context, 'Ошибка входа: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitMfa() async {
    final uid = await widget.prefs.userId();
    if (uid == null || uid.isEmpty) {
      if (mounted) AppSnack.show(context, 'Сначала выполните логин');
      return;
    }
    setState(() => _busy = true);
    try {
      await _authApi.verifyMfa(userId: uid, code: _mfaCtl.text.trim());
      if (mounted) AppSnack.show(context, '2FA подтвержден');
    } catch (e) {
      if (mounted) AppSnack.show(context, 'Ошибка 2FA: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleGlobalNotifications(bool v) async {
    await widget.prefs.setNotificationsEnabled(v);
    if (mounted) {
      setState(() {});
      AppSnack.show(context, v ? 'Уведомления включены' : 'Уведомления выключены');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MessengerBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Security & Subscription')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SecureSectionTitle(
              'Сервер и аккаунт',
              subtitle: 'Авторизация, подписка, connect-token и защита устройства',
            ),
            const SizedBox(height: 12),
            SecureCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Локальные настройки интерфейса не затрагивают ключи и чаты.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverUrlCtl,
                    decoration: const InputDecoration(
                      labelText: 'Server Base URL',
                      hintText: 'https://hm491715.webhm.pro',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _serverPinCtl,
                    decoration: const InputDecoration(
                      labelText: 'TLS Pin (header based)',
                      hintText: 'sha256/...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(onPressed: _saveServer, child: const Text('Сохранить сервер')),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailCtl,
                    decoration: const InputDecoration(labelText: 'Email аккаунта'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passCtl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Пароль аккаунта'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _loginServer,
                    child: const Text('Войти в серверный аккаунт'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _mfaCtl,
                    decoration: const InputDecoration(labelText: '2FA код владельца'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _submitMfa,
                    child: const Text('Подтвердить 2FA'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SecureCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SecureSectionTitle('Текущий серверный профиль'),
                  const SizedBox(height: 8),
                  FutureBuilder<String?>(
                    future: widget.prefs.nickname(),
                    builder: (context, sNick) => FutureBuilder<String?>(
                      future: widget.prefs.connectToken(),
                      builder: (context, sTok) => FutureBuilder<String>(
                        future: widget.prefs.subscriptionStatus(),
                        builder: (context, sSub) => Text(
                          'Nickname: ${sNick.data ?? '-'}\n'
                          'Connect token: ${sTok.data ?? '-'}\n'
                          'Подписка: ${sSub.data ?? 'trial'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SecureCard(
              child: Column(
                children: [
                  FutureBuilder<bool>(
                    future: widget.prefs.licenseEnforcementEnabled(),
                    builder: (context, snapshot) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.verified_user_outlined),
                      title: const Text('Жесткая проверка лицензии'),
                      subtitle:
                          const Text('Без валидной серверной лицензии приложение блокирует secure-функции'),
                      value: snapshot.data ?? true,
                      onChanged: (v) async {
                        await widget.prefs.setLicenseEnforcementEnabled(v);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                  FutureBuilder<bool>(
                    future: widget.prefs.notificationsEnabled(),
                    builder: (context, snapshot) {
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.notifications_active_outlined),
                        title: const Text('Уведомления'),
                        subtitle: const Text('Глобально включить/выключить все push о новых сообщениях'),
                        value: snapshot.data ?? true,
                        onChanged: _toggleGlobalNotifications,
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  FilledButton.tonal(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Сбросить настройки?'),
                          content: const Text(
                            'Будут сброшены подсказки при показе ключей и прочие локальные флаги. '
                            'Пароль, ключи и переписка не изменятся.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сбросить')),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        await widget.prefs.resetUiPreferences();
                        if (context.mounted) {
                          AppSnack.show(context, 'Настройки интерфейса сброшены.');
                        }
                      }
                    },
                    child: const Text('Сбросить настройки приложения'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Полное удаление данных — в боковом меню «Удалить все данные».',
                    style: TextStyle(color: cs.secondary.withValues(alpha: 0.9), fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
