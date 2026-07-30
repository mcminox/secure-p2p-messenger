# Secure P2P Messenger

Локальный P2P-мессенджер на Flutter (Android, iOS, Windows) с шифрованием чатов и опциональным PHP-бэкендом для signaling/лицензий.

## Стек

- Flutter 3 / Dart
- Ed25519, X25519, ChaCha20-Poly1305
- WebRTC DataChannel
- PHP backend (`backend-php/`)

## Запуск

```bash
flutter create . --platforms=android,ios,windows
flutter pub get
flutter run -d windows
```

Сборка релиза: `.\tools\build_release.ps1`.

## Структура

| Путь | Назначение |
|------|------------|
| `lib/` | клиент |
| `backend-php/` | API, signaling, billing |
| `docs/` | security / API |
| `android/`, `ios/`, `windows/` | платформы |
