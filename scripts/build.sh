#!/bin/bash
# 用法:  scripts/build.sh [test|ipa|all]   (默认 all)
#   test  生成工程 → 在 iOS 模拟器上跑单元测试 + UI 测试
#   ipa   生成工程 → Release 编译 → 打包未签名 build/AudioExtractor-unsigned.ipa
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-all}"
XCODEGEN_VERSION="2.44.1"
mkdir -p build tools

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

command -v xcodebuild >/dev/null || { echo "未找到 xcodebuild，请先安装 Xcode 并打开一次"; exit 1; }

# 1. XcodeGen（不需要 Homebrew，直接下载官方 release）
if command -v xcodegen >/dev/null; then
  XCODEGEN=xcodegen
else
  XCODEGEN=tools/xcodegen/bin/xcodegen
  if [ ! -x "$XCODEGEN" ]; then
    log "下载 XcodeGen $XCODEGEN_VERSION"
    curl -fsSL -o tools/xcodegen.zip "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
    unzip -q -o tools/xcodegen.zip -d tools
  fi
fi
log "生成 Xcode 工程"
"$XCODEGEN" generate --quiet

run_tests() {
  UDID=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' || true)
  if [ -z "$UDID" ]; then
    log "没有可用的 iPhone 模拟器，下载 iOS 平台（体积较大，需要几分钟）"
    xcodebuild -downloadPlatform iOS
    UDID=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
  fi
  log "运行测试（模拟器 ${UDID}）"
  rm -rf build/Tests.xcresult
  set +e
  xcodebuild test \
    -project AudioExtractor.xcodeproj -scheme AudioExtractor \
    -destination "id=$UDID" \
    -derivedDataPath build/DerivedData-test \
    -resultBundlePath build/Tests.xcresult \
    > build/test.log 2>&1
  STATUS=$?
  set -e
  grep -E "error:|Test Case .* (passed|failed)|Executed [0-9]+ tests?|\*\* TEST" build/test.log | tail -80
  if [ $STATUS -ne 0 ]; then echo "❌ 测试失败，完整日志: build/test.log"; exit $STATUS; fi
  echo "✅ 测试全部通过"
}

build_ipa() {
  log "Release 编译（不签名）"
  set +e
  xcodebuild build \
    -project AudioExtractor.xcodeproj -scheme AudioExtractor -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    > build/build.log 2>&1
  STATUS=$?
  set -e
  if [ $STATUS -ne 0 ]; then grep -E "error:" build/build.log | head -40; echo "❌ 编译失败，完整日志: build/build.log"; exit $STATUS; fi
  APP=build/DerivedData/Build/Products/Release-iphoneos/AudioExtractor.app
  rm -rf build/Payload build/AudioExtractor-unsigned.ipa
  mkdir -p build/Payload
  cp -R "$APP" build/Payload/
  (cd build && zip -qry AudioExtractor-unsigned.ipa Payload && rm -rf Payload)
  log "完成: $(pwd)/build/AudioExtractor-unsigned.ipa ($(du -h build/AudioExtractor-unsigned.ipa | cut -f1))"
}

case "$MODE" in
  test) run_tests ;;
  ipa) build_ipa ;;
  all) run_tests; build_ipa ;;
  *) echo "用法: $0 [test|ipa|all]"; exit 2 ;;
esac
