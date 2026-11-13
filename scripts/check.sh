#!/bin/zsh
# 门禁：构建全部产物（App 与各库）并跑全部测试，任何一步失败就以非零码退出。
# 只编译和跑单元测试，不启动 App、不碰屏幕和窗口
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build（全部产物）"
swift build

echo "==> swift test"
swift test

echo "✅ check 通过"
