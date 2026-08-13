#!/bin/bash
# 在 macOS runner 上编译 iOS arm64 dylib
set -euo pipefail

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "iOS SDK: $SDK"

clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=13.0 \
  -fobjc-arc \
  -fobjc-exceptions \
  -Wno-deprecated-declarations \
  -Wl,-install_name,@executable_path/wechat-ai.dylib \
  -dynamiclib \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -framework Security \
  -lsqlite3 \
  -o wechat-ai.dylib \
  AIContext.m AIAPIClient.m AISettings.m AIPromptEditorViewController.m AIProfileListViewController.m WeChatAITweak.m

# 打一个 ad-hoc 签名，不影响 TrollFools/越狱使用
codesign -f -s - wechat-ai.dylib || true

file wechat-ai.dylib
echo "构建完成: $(pwd)/wechat-ai.dylib"
