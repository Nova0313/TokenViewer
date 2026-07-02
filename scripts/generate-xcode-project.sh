#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if command -v xcodegen >/dev/null 2>&1; then
    XCODEGEN="$(command -v xcodegen)"
elif [ -x /opt/homebrew/bin/xcodegen ]; then
    XCODEGEN="/opt/homebrew/bin/xcodegen"
elif [ -x /usr/local/bin/xcodegen ]; then
    XCODEGEN="/usr/local/bin/xcodegen"
else
    echo "缺少 XcodeGen。请先运行: brew install xcodegen"
    exit 1
fi

cd "$ROOT"
"$XCODEGEN" generate
echo "Generated $ROOT/TokenViewer.xcodeproj"
