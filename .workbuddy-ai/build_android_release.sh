#!/usr/bin/env bash
# Build a SIGNED Karing release APK locally, without GitHub Actions.
#
# Replaces .github/workflows/build.yml's android job, which cannot run while the
# GitHub account is locked for billing. Produces the same artifacts the CI would
# have, named to match upstream's pkg_android.bat:
#
#   dist/karing_<version>_android_arm.apk              (universal)
#   dist/karing_<version>_android_arm64-v8a.apk
#   dist/karing_<version>_android_armeabi-v7a.apk
#
# TWO THINGS THIS SCRIPT EXISTS TO HANDLE, both of which fail confusingly by hand:
#
#  1. MEMORY. This machine is commit-bound, not CPU-bound: 23.7 GB RAM plus a
#     manually-sized 9.4 GB pagefile gives a ~32.9 GB commit limit. When that is
#     exhausted the Gradle JVM dies with a NATIVE allocation failure
#     ("malloc failed ... Chunk::new", arena.cpp) that never mentions memory
#     limits in the way you would expect. See the memory precheck below.
#
#  2. key.properties. android/app/build.gradle.kts reads it during CONFIGURATION
#     (`Properties().apply { keystore.inputStream()... }`) for EVERY build type,
#     so a missing file breaks even an unsigned build.
#
# NOTE ON JAVA: `flutter config --list` reports a `jdk-dir`, and Flutter uses
# that for Gradle -- it WINS over JAVA_HOME. On this box it points at Android
# Studio's bundled JBR (Java 21). That is fine: build.gradle.kts sets
# sourceCompatibility/targetCompatibility = VERSION_17, which means "emit Java 17
# bytecode", and a JDK 21 runtime produces that happily. Do not "fix" the JDK
# version here; the crash was memory, not Java. The script reports which JDK is
# actually in effect rather than assuming.
#
# Usage:  ./.workbuddy-ai/build_android_release.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
echo "repo: $REPO"

# --- toolchain -----------------------------------------------------------------
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

echo "=== toolchain ==="
echo "  flutter -> $(command -v flutter)"
# Report the JDK that will ACTUALLY run Gradle, which is Flutter's jdk-dir.
FLUTTER_JDK="$(flutter config --list 2>/dev/null | sed -n 's/.*jdk-dir: *//p' | tr -d '\r')"
if [ -n "$FLUTTER_JDK" ]; then
  echo "  gradle JDK (flutter jdk-dir) -> $FLUTTER_JDK"
  if [ -x "$FLUTTER_JDK/bin/java" ]; then
    "$FLUTTER_JDK/bin/java" -version 2>&1 | head -1 | sed 's/^/    /'
  fi
else
  echo "  gradle JDK -> (no jdk-dir set; falls back to JAVA_HOME / PATH)"
  java -version 2>&1 | head -1 | sed 's/^/    /'
fi

# --- memory precheck -----------------------------------------------------------
# The failure mode this guards against is a native OOM deep into the build, which
# costs several minutes and produces a 1 MB crash log rather than a clear error.
# `wmic` is removed on current Windows and `powershell.exe` cannot be invoked from
# this shell, so parse `systeminfo`. It is slow (~5s) but always present.
echo "=== memory precheck ==="
COMMIT_FREE_MB="$(systeminfo 2>/dev/null \
  | sed -n 's/^Virtual Memory: Available:[[:space:]]*\([0-9,]*\) MB.*/\1/p' \
  | tr -d ',' | head -1)"
if [ -n "$COMMIT_FREE_MB" ]; then
  echo "  commit headroom: ${COMMIT_FREE_MB} MB"
  if [ "$COMMIT_FREE_MB" -lt 6144 ]; then
    echo "" >&2
    echo "WARNING: only ${COMMIT_FREE_MB} MB of commit headroom. This build has been" >&2
    echo "         observed to need roughly 6-8 GB of peak commit, and when it runs" >&2
    echo "         out the Gradle JVM dies with a native 'malloc failed ... Chunk::new'" >&2
    echo "         crash rather than a clear out-of-memory error." >&2
    echo "         Close memory-heavy apps (AI agents, Chrome, Docker), or raise the" >&2
    echo "         pagefile (currently manually sized at ~9 GB). Continuing anyway." >&2
    echo "" >&2
  fi
else
  echo "  (could not read commit headroom; continuing)"
fi

# --- signing material ----------------------------------------------------------
echo "=== signing material ==="
if [ ! -f android/key.properties ]; then
  echo "ERROR: android/key.properties is missing. Gradle reads it at configuration" >&2
  echo "       time for every build type, so the build cannot even start." >&2
  exit 1
fi
STORE="android/$(grep '^storeFile.release=' android/key.properties | cut -d= -f2- | tr -d '\r')"
if [ ! -f "$STORE" ]; then
  echo "ERROR: keystore not found at $STORE (from storeFile.release)." >&2
  exit 1
fi
echo "  key.properties : present"
echo "  keystore       : $STORE ($(stat -c%s "$STORE") bytes)"
echo "  alias          : $(grep '^keyAlias.release=' android/key.properties | cut -d= -f2- | tr -d '\r')"

# --- build ---------------------------------------------------------------------
VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//;s/+.*//' | tr -d '\r')"
echo "=== building release APK (version $VERSION) ==="
flutter build apk --release

# --- collect + rename to upstream's convention ---------------------------------
SRC="build/app/outputs/flutter-apk"
echo "=== collecting artifacts ==="
mkdir -p dist
# `arm` is upstream's name for the UNIVERSAL apk (isUniversalApk = true in
# android/app/build.gradle.kts), not an armeabi-v7a build.
copy() {
  if [ -f "$SRC/$1" ]; then
    cp "$SRC/$1" "dist/$2"
    echo "  $1 -> $2"
  elif [ "${3:-}" = required ]; then
    echo "ERROR: $SRC/$1 not found. Did the ABI splits in build.gradle.kts change?" >&2
    exit 1
  else
    echo "  skip $1 (absent)"
  fi
}
copy app-release.apk             "karing_${VERSION}_android_arm.apk"          required
copy app-arm64-v8a-release.apk   "karing_${VERSION}_android_arm64-v8a.apk"
copy app-armeabi-v7a-release.apk "karing_${VERSION}_android_armeabi-v7a.apk"

# --- verify the APK is genuinely signed ----------------------------------------
# A `flutter build apk --release` with a broken signingConfig can still emit an
# APK; it is just unsigned, and it installs nowhere. Verify rather than assume.
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-C:/Users/Teamcheh/AppData/Local/Android/Sdk}}"
APKSIGNER="$(ls "$SDK"/build-tools/*/apksigner.bat 2>/dev/null | sort -V | tail -1 || true)"

echo "=== signature verification ==="
if [ -z "$APKSIGNER" ]; then
  echo "  WARNING: apksigner not found under $SDK/build-tools - cannot verify." >&2
else
  echo "  using $(basename "$(dirname "$APKSIGNER")")/apksigner"
  for apk in dist/*.apk; do
    printf "  %-46s " "$(basename "$apk")"
    if "$APKSIGNER" verify --print-certs "$apk" >/tmp/_apksig.txt 2>&1; then
      # surface WHICH key signed it, so a debug-key mixup is visible
      sed -n 's/^Signer #1 certificate DN: /signed by: /p' /tmp/_apksig.txt | head -1 | sed 's/^/  /'
    else
      echo "UNSIGNED or INVALID"
      head -3 /tmp/_apksig.txt | sed 's/^/      /'
    fi
  done
  rm -f /tmp/_apksig.txt
fi

echo "=== done ==="
ls -la dist/*.apk | sed 's/^/  /'
