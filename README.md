# Secure P2P Messenger

> **Личное сообщение.** Это лишь демонстрационный экземпляр одного из проектов, над которыми я работал. Репозиторий выложен для портфолио и ознакомления, а не как готовый продукт «бери и используй». Код и материалы защищены проприетарной лицензией и авторским правом: копировать, переиспользовать, сдавать как свою работу, встраивать фрагменты в другие проекты или распространять без моего письменного разрешения нельзя. Публичный доступ ≠ разрешение на копирование. Подробности — в `NOTICE`, `COPYRIGHT` и `LICENSE`.

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

## Права и лицензия

См. `NOTICE`, `COPYRIGHT`, `LICENSE`. Все права защищены.
