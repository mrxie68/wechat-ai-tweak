#!/bin/bash
# 在 ubuntu runner 上把 dylib 打成越狱 deb
set -euo pipefail

mkdir -p packaging/Library/MobileSubstrate/DynamicLibraries
cp wechat-ai.dylib packaging/Library/MobileSubstrate/DynamicLibraries/
chmod 755 packaging/Library/MobileSubstrate/DynamicLibraries/wechat-ai.dylib

dpkg-deb -b packaging wechat-ai_0.1.0_iphoneos-arm.deb
echo "打包完成: $(pwd)/wechat-ai_0.1.0_iphoneos-arm.deb"
