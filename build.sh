#!/bin/bash
# Сборка Dakt: swift build собирает бинарник, скрипт складывает бандл,
# рисует иконку, подписывает и ставит в /Applications.
#
#   ./build.sh                 собрать и установить в /Applications
#   ./build.sh --check         только скомпилировать (отладочная сборка)
#   ./build.sh --out DIR       собрать бандл в DIR, не устанавливать
#   ./build.sh --universal     бинарник под Apple Silicon и Intel сразу
#
# Переменные окружения:
#   DAKT_SIGN_ID   имя удостоверения для подписи (по умолчанию «DaktRecorder Local»)
set -euo pipefail

cd "$(dirname "$0")"

CHECK_ONLY=0
OUT_DIR=""
UNIVERSAL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1 ;;
        --out) shift; OUT_DIR="${1:-}"; [ -n "$OUT_DIR" ] || { echo "--out требует папку"; exit 2; } ;;
        --universal) UNIVERSAL=1 ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "Неизвестный аргумент: $1"; exit 2 ;;
    esac
    shift
done

if ! command -v swift >/dev/null 2>&1; then
    echo "Не найден swift. Установи инструменты разработчика: xcode-select --install"
    exit 1
fi

if [ "$CHECK_ONLY" = 1 ]; then
    swift build
    echo "Компиляция прошла, установка пропущена (--check)."
    exit 0
fi

# Релизная сборка. Универсальный бинарник нужен, когда приложение уезжает на
# чужой мак и неизвестно, Intel там или Apple Silicon.
ARCH_FLAGS=()
if [ "$UNIVERSAL" = 1 ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
    echo "Собираю универсальный бинарник (arm64 + x86_64)…"
else
    echo "Собираю для $(uname -m)…"
fi
# Пустой массив под set -u в bash 3.2 (штатном на macOS) считается
# неопределённым, поэтому раскрываем его через ${arr[@]+...}.
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/DaktRecorder"

# Бандл складываем во временной папке вне домашней, а не рядом с исходниками.
# Готовый бандл, полежавший там, где система следит за файлами, она успевает
# зарегистрировать - и рядом с установленным появляется второй такой же.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Dakt.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/DaktRecorder"

# Иконка приложения. Исходник - Resources/AppIcon.png: квадрат 1024 с прозрачными
# углами, как того ждёт macOS. Все размеры набора получаем из него.
if command -v iconutil >/dev/null 2>&1 && [ -f Resources/AppIcon.png ]; then
    SET="$STAGE/DaktRecorder.iconset"
    mkdir -p "$SET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" Resources/AppIcon.png \
            --out "$SET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" Resources/AppIcon.png \
            --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$SET" -o "$APP/Contents/Resources/DaktRecorder.icns"
    rm -rf "$SET"
else
    echo "iconutil или Resources/AppIcon.png недоступны - приложение соберётся без иконки."
fi

# Постоянное удостоверение вместо ad-hoc. macOS привязывает выданные права
# к подписи, а у ad-hoc она меняется при каждой сборке: система видит новое
# приложение и снова спрашивает доступ к микрофону и записи экрана.
# Создать удостоверение один раз: см. README, раздел «Подпись и разрешения».
SIGN_ID="${DAKT_SIGN_ID:-DaktRecorder Local}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" --identifier local.daktrecorder \
        --options runtime --entitlements Entitlements.plist "$APP" >/dev/null
    echo "Подписано удостоверением: $SIGN_ID"
else
    codesign --force --sign - --identifier local.daktrecorder "$APP" >/dev/null
    echo "Удостоверение '$SIGN_ID' не найдено, подпись ad-hoc."
    echo "Права доступа будут слетать при каждой сборке - см. README."
fi

if [ -n "$OUT_DIR" ]; then
    mkdir -p "$OUT_DIR"
    rm -rf "$OUT_DIR/Dakt.app"
    mv "$APP" "$OUT_DIR/Dakt.app"
    echo "Готово: $OUT_DIR/Dakt.app"
    exit 0
fi

# Ставим приложение в /Applications и не оставляем копию рядом с исходниками.
# Два одинаковых бандла на диске macOS путают: выданные права она привязывает
# к приложению, а какое из двух перед ней - решает по-своему.
DEST="/Applications/Dakt.app"
rm -rf "$DEST"
mv "$APP" "$DEST"

echo "Готово: $DEST"
echo "Запуск: open \"$DEST\""
