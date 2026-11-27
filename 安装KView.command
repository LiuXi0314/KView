#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$DIR/KView.app"
APP_DST="/Applications/KView.app"
OLD_APP="/Applications/KMark.app"

if [ ! -d "$APP_SRC" ]; then
    echo "未找到 $APP_SRC，请先运行 build_app.sh 编译。"
    exit 1
fi

if [ -d "$OLD_APP" ]; then
    rm -rf "$OLD_APP"
fi

rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true

echo "✅ KView 已安装到 /Applications/KView.app，正在启动..."
open "$APP_DST"
