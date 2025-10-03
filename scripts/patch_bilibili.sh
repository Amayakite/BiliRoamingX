#!/usr/bin/env bash
set -euo pipefail

# patch_bilibili.sh
# Downloads bilibili.apk and revanced-cli.jar (if missing), copies integrations/patch-bundle from CI artifacts dir,
# attempts full patch, and falls back to a minimal reliable set. Writes output APK path to patch-result.txt.

APK_URL=${APK_URL:-"https://dl.hdslb.com/mobile/latest/android64/iBiliPlayer-bili.apk"}
ARTIFACTS_DIR=${ARTIFACTS_DIR:-"ci-artifacts"}
BUILD_DIR=${BUILD_DIR:-"build"}

mkdir -p "$BUILD_DIR"

echo "[patch] Using APK_URL=$APK_URL"
echo "[patch] Using ARTIFACTS_DIR=$ARTIFACTS_DIR"

# Locate artifacts
shopt -s globstar nullglob
INTEGRATIONS=$(ls -1 "$ARTIFACTS_DIR"/**/BiliRoamingX-integrations-*.apk | head -n1 || true)
PATCH_BUNDLE=$(ls -1 "$ARTIFACTS_DIR"/**/BiliRoamingX-patches-*.jar | head -n1 || true)

if [[ -z "$INTEGRATIONS" || -z "$PATCH_BUNDLE" ]]; then
  echo "::error::Cannot find integrations apk or patches jar in artifacts" >&2
  exit 1
fi

cp -v "$INTEGRATIONS" "$BUILD_DIR/"
cp -v "$PATCH_BUNDLE" "$BUILD_DIR/"

# Download inputs if missing
if [[ ! -f "$BUILD_DIR/bilibili.apk" ]]; then
  curl -fL --retry 3 -o "$BUILD_DIR/bilibili.apk" "$APK_URL"
fi
if [[ ! -f "$BUILD_DIR/revanced-cli.jar" ]]; then
  curl -fL --retry 3 -o "$BUILD_DIR/revanced-cli.jar" \
    https://github.com/zjns/revanced-cli/releases/latest/download/revanced-cli.jar
fi

pushd "$BUILD_DIR" >/dev/null

INTEGRATIONS_BASENAME=$(basename "$INTEGRATIONS")
PATCH_BUNDLE_BASENAME=$(basename "$PATCH_BUNDLE")

echo "[patch] Full patch attempt"
set +e
JAVA_TOOL_OPTIONS="-Xmx2048m -XX:+UseSerialGC" java -jar revanced-cli.jar patch \
  --merge "$INTEGRATIONS_BASENAME" \
  --patch-bundle "$PATCH_BUNDLE_BASENAME" \
  --signing-levels 1 \
  -o bilibili-patched-full.apk \
  bilibili.apk | tee bilibili-patch-full.log
CODE=$?
FULL_SUCCESS=0
if [[ $CODE -eq 0 && -f bilibili-patched-full.apk ]]; then
  FULL_SUCCESS=1
fi
set -e

if [[ $FULL_SUCCESS -ne 1 ]]; then
  echo "[patch] Full attempt failed; fallback to minimal set"
  JAVA_TOOL_OPTIONS="-Xmx1024m -XX:+UseSerialGC" java -jar revanced-cli.jar patch \
    --exclusive \
    --merge "$INTEGRATIONS_BASENAME" \
    --patch-bundle "$PATCH_BUNDLE_BASENAME" \
    --include "Integrations" \
    --include "BiliRoamingX settings entrance" \
    --include "Config" \
    --include "Config integration" \
    --include "Main activity patch" \
    --include "Bili library patch" \
    --include "Json" \
    --include "OkHttp" \
    --include "Override certificate pinning" \
    --include "BLog" \
    --include "Pegasus hook" \
    --signing-levels 1 \
    -o bilibili-patched-min.apk \
    bilibili.apk | tee bilibili-patch-min.log
  OUT="bilibili-patched-min.apk"
else
  OUT="bilibili-patched-full.apk"
fi

ls -lh "$OUT"
sha256sum "$OUT" | tee bilibili-patched.sha256
echo "$OUT" | tee patch-result.txt

popd >/dev/null

echo "[patch] Done. Output at $BUILD_DIR/$OUT"
