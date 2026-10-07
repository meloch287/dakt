# Сборка и релизы

## Инструменты

- macOS, Xcode со Swift 6.2+ и SDK macOS 26.
- `xcode-select` должен указывать на выбранный Xcode.
- Для DMG: Python 3.10+ и зависимости из [requirements-release.txt](../Tools/requirements-release.txt).
- Для публикации: GitHub CLI с авторизацией и SSH-доступом.

У работающего Dakt нет внешних пакетных зависимостей. Python и dmgbuild нужны только при подготовке установочного образа.

## Проверки и приложение

```sh
swift test
./build.sh --check
./build.sh --universal --out dist
codesign --verify --deep --strict dist/Dakt.app
lipo -archs dist/Dakt.app/Contents/MacOS/DaktRecorder
```

Последняя команда должна вывести `x86_64 arm64` (порядок может отличаться). Это проверка состава бинарника; она не заменяет запуск на реальном Intel Mac.

`./build.sh --out dist` собирает только архитектуру текущего компьютера. Вызов без `--out` устанавливает приложение в `/Applications/Dakt.app`.

## DMG

```sh
./Tools/package-dmg.sh dist/Dakt.app dist
```

Скрипт создаёт локальное окружение в `.build/dmg-tools`, устанавливает закреплённую версию инструмента, рисует фон и собирает образ. В образ входят Dakt.app, ссылка на Applications, инструкция и лицензия. Личные настройки, аудиофайлы, резюме и ключи не копируются.

Имя содержит версию из Info.plist и архитектуру, например `Dakt-v2.4.1-universal.dmg`. Рядом находится одноимённый файл `.sha256`.

Проверка:

```sh
cd dist
shasum -a 256 -c Dakt-v2.4.1-universal.dmg.sha256
hdiutil verify Dakt-v2.4.1-universal.dmg
```

## Подпись

`build.sh` использует удостоверение **DaktRecorder Local** или значение `DAKT_SIGN_ID`. При отсутствии удостоверения бандл подписывается ad-hoc. Для выпуска с другим доступным удостоверением:

```sh
DAKT_SIGN_ID="имя вашего удостоверения" ./build.sh --universal --out dist
```

Локальная подпись помогает сохранять разрешения на одном Mac, но не заменяет сертификат **Developer ID Application** и нотарификацию Apple. Текущий публичный релиз **не нотаризован**. Автоматической нотарификации в workflow нет; секреты сертификата и аккаунта Apple в проект не входят.

## Нативные снимки и проверка окна

```sh
swift build
.build/debug/DaktRecorder --render-previews .build/previews
```

Режим использует только фикстуры и не читает ключи, не захватывает аудио и не обращается к сети. Нужна графическая сессия macOS. Проверяются несколько размеров, lock/unlock и восстановление окна.

Примеры дополнительных диагностик:

```sh
.build/debug/DaktRecorder --preview
.build/debug/DaktRecorder --check-proxy
.build/debug/DaktRecorder --benchmark-audio /путь/к/тестовому-вопросу.wav
```

Две последние команды делают реальные запросы к выбранному корпоративному API. Аудиобенчмарк выводит распознанную тестовую фразу и ответ: используйте синтетические данные.

## GitHub Actions

- **CI** запускает тесты, проверяет сборку и сохраняет ZIP бандла. ZIP сохраняет структуру .app.
- **Release** запускается при теге `v*` или вручную для существующего тега, сверяет его с Info.plist, проверяет код, собирает универсальный DMG и публикует его вместе с SHA‑256.
- Обычный CI имеет права только на чтение. Публикация релиза требует `contents: write`.

Перед тегом обновите Info.plist и CHANGELOG. Тег должен указывать на проверенный коммит. Workflow не переписывает существующие релизные файлы.

Первый публичный релиз может быть опубликован из проверенной локальной сборки:

```sh
gh release create v2.4.1 \
  dist/Dakt-v2.4.1-universal.dmg \
  dist/Dakt-v2.4.1-universal.dmg.sha256 \
  --repo meloch287/dakt --verify-tag \
  --title "Dakt 2.4.1" --notes-file Documentation/releases/v2.4.1.md
```
