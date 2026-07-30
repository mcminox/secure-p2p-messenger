# Secure P2P Messenger

> **Personal note (EN).** This is only a demonstration instance of one of the projects I worked on. The repository is published for portfolio and review — not as a ready-made product to take and use. The code and materials are protected by a proprietary license and copyright: you may not copy, reuse, submit as your own work, embed fragments in other projects, or redistribute without my prior written permission. Public access ≠ permission to copy. Details: NOTICE, COPYRIGHT, LICENSE.

<details>
<summary>Translations / 翻訳 / Traduções / Übersetzungen / Переклади / Переводы</summary>

### English
This is only a demonstration instance of one of the projects I worked on. The repository is published for portfolio and review — not as a ready-made product to take and use. The code and materials are protected by a proprietary license and copyright: you may not copy, reuse, submit as your own work, embed fragments in other projects, or redistribute without my prior written permission. Public access ≠ permission to copy. Details: NOTICE, COPYRIGHT, LICENSE.

### 日本語
これは、私が関わったプロジェクトのデモンストレーション用サンプルです。ポートフォリオ／確認のために公開しており、自由に使える完成品ではありません。コードと資料は独自ライセンスおよび著作権で保護されています。事前の書面による許可なく、コピー、再利用、自分の成果物としての提出、他プロジェクトへの断片の組み込み、再配布はできません。公開されていること＝複製の許可ではありません。詳細は NOTICE、COPYRIGHT、LICENSE を参照してください。

### Português
Este é apenas um exemplar de demonstração de um dos projetos em que trabalhei. O repositório foi publicado para portfólio e avaliação — não como um produto pronto para usar. O código e os materiais estão protegidos por licença proprietária e direitos autorais: não é permitido copiar, reutilizar, apresentar como trabalho próprio, incorporar fragmentos noutros projetos ou redistribuir sem a minha autorização prévia por escrito. Acesso público ≠ permissão para copiar. Detalhes: NOTICE, COPYRIGHT, LICENSE.

### Deutsch
Dies ist nur eine Demonstrationsinstanz eines der Projekte, an denen ich gearbeitet habe. Das Repository dient dem Portfolio und der Begutachtung — nicht als fertiges Produkt zur freien Nutzung. Code und Materialien sind durch eine proprietäre Lizenz und Urheberrecht geschützt: Kopieren, Weiterverwenden, als eigene Arbeit einreichen, Fragmente in andere Projekte einbauen oder Weiterverbreiten ohne meine vorherige schriftliche Erlaubnis ist nicht gestattet. Öffentlicher Zugang ≠ Kopiererlaubnis. Details: NOTICE, COPYRIGHT, LICENSE.

### Українська
Це лише демонстраційний екземпляр одного з проєктів, над якими я працював. Репозиторій викладено для портфоліо та ознайомлення — не як готовий продукт «бери й використовуй». Код і матеріали захищені пропрієтарною ліцензією та авторським правом: копіювати, повторно використовувати, здавати як свою роботу, вбудовувати фрагменти в інші проєкти чи поширювати без мого письмового дозволу не можна. Публічний доступ ≠ дозвіл на копіювання. Деталі: NOTICE, COPYRIGHT, LICENSE.

### Русский
Это лишь демонстрационный экземпляр одного из проектов, над которыми я работал. Репозиторий выложен для портфолио и ознакомления — не как готовый продукт «бери и используй». Код и материалы защищены проприетарной лицензией и авторским правом: копировать, переиспользовать, сдавать как свою работу, встраивать фрагменты в другие проекты или распространять без моего письменного разрешения нельзя. Публичный доступ ≠ разрешение на копирование. Подробности: NOTICE, COPYRIGHT, LICENSE.

</details>

Local P2P messenger on Flutter (Android, iOS, Windows) with chat encryption and an optional PHP backend for signaling/licensing.

## Stack

- Flutter 3 / Dart
- Ed25519, X25519, ChaCha20-Poly1305
- WebRTC DataChannel
- PHP backend (`backend-php/`)

## Run

```bash
flutter create . --platforms=android,ios,windows
flutter pub get
flutter run -d windows
```

Release build: `.\tools\build_release.ps1`.

## Layout

| Path | Purpose |
|------|---------|
| `lib/` | client |
| `backend-php/` | API, signaling, billing |
| `docs/` | security / API |
| `android/`, `ios/`, `windows/` | platforms |

## Rights & license

See NOTICE, COPYRIGHT, and LICENSE. All rights reserved.