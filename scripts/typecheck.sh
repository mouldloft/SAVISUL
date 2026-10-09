#!/bin/zsh
# Fast compile check without linking: ./scripts/typecheck.sh
cd "$(dirname "$0")/.."
swiftc -typecheck -parse-as-library \
  -target arm64-apple-macos14.2 \
  -sdk "$PWD/.build/MacOSX.sdk" \
  -vfsoverlay "$PWD/.build/overlay.json" \
  -module-cache-path "$PWD/.build/module-cache" \
  -I Sources/SMCBridge/include \
  Sources/SAVISUL/**/*.swift 2>&1 | grep -E '^Sources.*error:' -A4 | head -${1:-120}
