#!/usr/bin/env bash
# Builds MEREYTOI TEST: package kz.mereytoi.mereytoi_app.qa, signed by the upload
# key, installable next to the app from Google Play. See docs/android-builds.md.
#
#   flutter/tool/build_test_apk.sh                  # https://mereytoi.kz
#   flutter/tool/build_test_apk.sh --api URL        # a local stand for QA
#
# Stops if the result isn't that package and that signature: the Google Maps key
# only allows this exact pair.
set -euo pipefail

EXPECTED_PACKAGE="kz.mereytoi.mereytoi_app.qa"
EXPECTED_SHA1="C2:81:AB:DB:1E:A9:81:FD:CC:CC:13:6E:F0:B1:F1:29:C8:BF:18:65"

api=""
if [[ "${1:-}" == "--api" ]]; then
  api="${2:?--api needs a URL}"
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--api URL]" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

args=(--release --target-platform android-arm64 --android-project-arg=mereytoiTest=true)
[[ -n "$api" ]] && args+=("--dart-define=API_BASE_URL=$api")
flutter build apk "${args[@]}"

sdk="$(sed -n 's/^sdk.dir=//p' android/local.properties)"
build_tools="$(ls -d "$sdk"/build-tools/* | sort -V | tail -1)"
built="build/app/outputs/flutter-apk/app-release.apk"

package="$("$build_tools/aapt" dump badging "$built" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
sha1="$("$build_tools/apksigner" verify --print-certs "$built" \
  | sed -n 's/.*certificate SHA-1 digest: //p' | head -1 \
  | tr 'a-f' 'A-F' | sed 's/../&:/g; s/:$//')"

if [[ "$package" != "$EXPECTED_PACKAGE" || "$sha1" != "$EXPECTED_SHA1" ]]; then
  echo "WRONG BUILD: package=$package sha1=$sha1" >&2
  echo "expected:    package=$EXPECTED_PACKAGE sha1=$EXPECTED_SHA1" >&2
  exit 1
fi

mkdir -p build/test-copy
output="build/test-copy/mereytoi-test.apk"
cp "$built" "$output"
echo "package: $package"
echo "SHA-1:   $sha1"
echo "API:     ${api:-https://mereytoi.kz}"
echo "APK:     $PWD/$output"
