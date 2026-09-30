#!/usr/bin/env bash
#
# Build an unsigned Release .ipa for sideloading.
#
# Usage: scripts/build-ipa.sh [-o OUT_DIR] [-c CONFIG] [--clean]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="Aidoku"
CONFIG="Release"
OUT_DIR="$ROOT"
ARCHIVE="$ROOT/build/Aidoku.xcarchive"
CLEAN=0

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)        OUT_DIR="$2"; shift 2 ;;
        -c|--configuration) CONFIG="$2"; shift 2 ;;
        --clean)            CLEAN=1; shift ;;
        -h|--help)          usage 0 ;;
        *)                  echo "unknown option: $1" >&2; usage 1 ;;
    esac
done

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

[ "$CLEAN" -eq 1 ] && rm -rf "$ROOT/build"
rm -rf "$ARCHIVE"

echo "==> Archiving $SCHEME ($CONFIG)"
build() {
    xcodebuild \
        -project "$ROOT/Aidoku.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE" \
        -skipPackagePluginValidation \
        CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
        archive
}
if command -v xcbeautify >/dev/null 2>&1; then
    build | xcbeautify
else
    build
fi

APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || { echo "no .app in archive" >&2; exit 1; }

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist"; }
BUNDLE_ID="$(plist CFBundleIdentifier)"
VERSION="$(plist CFBundleShortVersionString)"
BUILD_NUMBER="$(plist CFBundleVersion)"
IPA="$OUT_DIR/$BUNDLE_ID.$VERSION.ipa"
DSYM_DIR="/Users/ryst/git/aidoku/dSYMs/$BUNDLE_ID.$VERSION.$BUILD_NUMBER-$(date -u '+%Y%m%d-%H%M%SZ')"

if [ ! -d "$ARCHIVE/dSYMs" ] || ! find "$ARCHIVE/dSYMs" -type d -name '*.dSYM' -print -quit | grep -q .; then
    echo "no dSYM files in archive" >&2
    exit 1
fi

echo "==> Saving dSYMs"
mkdir -p "$DSYM_DIR"
cp -R "$ARCHIVE/dSYMs/." "$DSYM_DIR/"

echo "==> Packaging $(basename "$IPA")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
# strip anything a signer would replace anyway
rm -rf "$STAGE/Payload/$(basename "$APP")/_CodeSignature" \
       "$STAGE/Payload/$(basename "$APP")/embedded.mobileprovision"
rm -f "$IPA"
(cd "$STAGE" && zip -qry "$IPA" Payload)

echo "==> $IPA ($(du -h "$IPA" | cut -f1))"
echo "==> $DSYM_DIR"
