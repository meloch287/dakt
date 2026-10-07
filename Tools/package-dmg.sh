#!/bin/bash
# Package an already-built Dakt.app; personal settings are never copied.
set -euo pipefail
DAKT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAKT_APP="${1:-$DAKT_ROOT/dist/Dakt.app}"
DAKT_OUTPUT="${2:-$DAKT_ROOT/dist}"
case "$DAKT_APP" in /*) ;; *) DAKT_APP="$PWD/$DAKT_APP" ;; esac
mkdir -p "$DAKT_OUTPUT"
DAKT_OUTPUT="$(cd "$DAKT_OUTPUT" && pwd)"

if [ ! -f "$DAKT_APP/Contents/Info.plist" ]; then
    echo "Не найден Dakt.app. Сначала выполните ./build.sh --universal --out dist" >&2
    exit 1
fi
codesign --verify --deep --strict "$DAKT_APP"
DAKT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DAKT_APP/Contents/Info.plist")"
if ! [[ "$DAKT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Ожидается версия вида 2.4.0 в Info.plist" >&2
    exit 1
fi
DAKT_ARCHS="$(lipo -archs "$DAKT_APP/Contents/MacOS/DaktRecorder")"
case "$DAKT_ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) DAKT_ARCH="universal" ;;
    arm64) DAKT_ARCH="arm64" ;;
    x86_64) DAKT_ARCH="x86_64" ;;
    *) echo "Неизвестные архитектуры: $DAKT_ARCHS" >&2; exit 1 ;;
esac
DAKT_NAME="Dakt-v$DAKT_VERSION-$DAKT_ARCH.dmg"
if [ -e "$DAKT_OUTPUT/$DAKT_NAME" ]; then
    echo "Образ уже существует: $DAKT_OUTPUT/$DAKT_NAME. Уберите прежний файл перед новой сборкой." >&2
    exit 1
fi

DAKT_VENV="$DAKT_ROOT/.build/dmg-tools"
if [ ! -x "$DAKT_VENV/bin/python" ]; then
    python3 -m venv "$DAKT_VENV"
fi
"$DAKT_VENV/bin/python" -m pip install --disable-pip-version-check -q -r "$DAKT_ROOT/Tools/requirements-release.txt"
swift "$DAKT_ROOT/Tools/DMGBackground.swift" "$DAKT_VENV/background.tiff" "$DAKT_VERSION"
"$DAKT_VENV/bin/dmgbuild" -s "$DAKT_ROOT/Tools/dmg-settings.py" \
    -D app="$DAKT_APP" -D root="$DAKT_ROOT" -D background="$DAKT_VENV/background.tiff" \
    "Dakt $DAKT_VERSION" "$DAKT_OUTPUT/$DAKT_NAME"
hdiutil verify "$DAKT_OUTPUT/$DAKT_NAME" >/dev/null
(
    cd "$DAKT_OUTPUT"
    shasum -a 256 "$DAKT_NAME" > "$DAKT_NAME.sha256"
)
echo "Готово: $DAKT_OUTPUT/$DAKT_NAME"
echo "SHA-256: $DAKT_OUTPUT/$DAKT_NAME.sha256"
