#!/usr/bin/env bash
# Rebuild the Karing-patched Android core (libbox.aar) from the local
# KaringX/sing-box fork via the sagernet gomobile fork.
#
# Mirrors cmd/internal/build_libbox/buildAndroidVariant() exactly, but:
#   * skips checkJavaVersion() (this box only has Oracle JDK 17, whose banner
#     says "java 17.0.13", not "openjdk 17" -- the check is cosmetic here)
#   * builds only the main variant (SDK 23). libbox-legacy.aar is referenced
#     nowhere in karing or vpn-service, so it is not needed.
set -euo pipefail

SDK="C:/Users/Teamcheh/AppData/Local/Android/Sdk"
NDK="$SDK/ndk/28.2.13676358"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_HOME="$SDK"
export ANDROID_NDK_HOME="$NDK"
export NDK="$NDK"
export JAVA_HOME="C:/Program Files/Java/jdk-17"
# NOTE: gomobile resolves javac via exec.LookPath("javac"), i.e. from PATH --
# it ignores JAVA_HOME. This box has Adoptium JDK 11 first on PATH, so we must
# prepend JDK 17. The entry must be in POSIX form or bash will not resolve it.
export PATH="/c/Program Files/Java/jdk-17/bin:$HOME/go/bin:$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin:$PATH"
# Keep Go/cgo scratch files out of the shared Windows Temp directory. That
# directory has stale compiler outputs locked by another process, which makes
# cgo fail while renaming *.s.tmp -> *.s with "Permission denied".
GOMOBILE_TMP="C:/Users/Teamcheh/.workbuddy-ai/karing-gomobile-tmp"
mkdir -p "$GOMOBILE_TMP"
export TMP="$GOMOBILE_TMP"
export TEMP="$GOMOBILE_TMP"
export TMPDIR="$GOMOBILE_TMP"
export GOTMPDIR="$GOMOBILE_TMP"

echo "=== toolchain sanity ==="
echo "javac -> $(command -v javac)"
javac -version 2>&1 | head -1

cd "D:/Flutter Projects/sing-box"

# gomobile writes build/<goarch>/libbox/go_libboxmain.go and does NOT clean up
# after itself if a previous run was interrupted, which then fails the next run
# with "The file exists." These dirs are untracked/git-ignored scratch output.
# Move them aside rather than deleting (a bulk rm trips the safe-delete guard,
# and this keeps the repo clean while staying reversible).
if [ -d build ]; then
  STALE="/tmp/gomobile-build-stale-$(date +%s)"
  mv build "$STALE"
  echo "moved stale gomobile scratch to $STALE"
fi

# NOTE: `with_naive_outbound` is deliberately omitted. This checkout has no
# naive outbound implementation left (protocol/naive/ is inbound-only and
# include/ only ships naive_outbound_stub.go), so the tag fails to link with
# "undefined: registerNaiveOutbound". The stock libbox.aar shipped with the
# stub compiled in, i.e. it was built without the tag too -- so this matches.
TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0,with_tailscale,ts_omit_logtail,ts_omit_ssh,ts_omit_drive,ts_omit_taildrop,ts_omit_webclient,ts_omit_doctor,ts_omit_capture,ts_omit_kube,ts_omit_aws,ts_omit_synology,ts_omit_bird"

LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=unknown -X internal/godebug.defaultGODEBUG=multipathtcp=0 -s -w -buildid= -checklinkname=0"

echo "=== env ==="
echo "ANDROID_HOME=$ANDROID_HOME"
echo "ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
echo "JAVA_HOME=$JAVA_HOME"
java -version 2>&1 | head -1
echo "=== gomobile ==="
gomobile version 2>&1 | head -2 || true
echo "=== building ==="
# The existing vpn-service API imports package `libbox` and the stock AAR
# loads `gojni`; preserve both ABI contracts instead of the upstream build
# command's newer io.nekohasekai/box defaults.
exec gomobile bind -v \
  -o libbox.aar \
  -target android \
  -androidapi 23 \
  -javapkg= \
  -libname=gojni \
  -trimpath \
  -buildvcs=false \
  -ldflags "$LDFLAGS" \
  -tags "$TAGS" \
  ./experimental/libbox
