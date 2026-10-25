#!/bin/zsh
# Unit tests. Command Line Tools build a test binary with the patched SDK.
# Xcode uses `swift test` and the SAVISULTests target in Package.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

# The Command Line Tools when they are installed, as ./build.sh uses, even if xcode-select picks Xcode.
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk ]]; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi
if ! xcode-select -p | grep -q CommandLineTools; then
  exec swift test
fi

if [[ ! -f .build/overlay.json || ! -f .build/MacOSX.sdk/.savisul-patched ]]; then
  echo "Compiler SDK is missing. Run ./build.sh once first." >&2
  exit 1
fi

mkdir -p .build
SDK="$PWD/.build/MacOSX.sdk"
SYS_SDK="$(xcrun --show-sdk-path)"
if [[ ! -f .build/smc_bridge.o ]]; then
  clang -c Sources/SMCBridge/smc_bridge.c \
    -I Sources/SMCBridge/include \
    -isysroot "$SYS_SDK" \
    -mmacosx-version-min=14.2 \
    -O2 \
    -o .build/smc_bridge.o
fi

# With Mould Engine present, the app is tested with the assistant compiled in, as it ships.
engine=()
if [[ -f MouldEngine/build.sh ]]; then
  zsh MouldEngine/build.sh release
  ENGINE_LIB="$PWD/MouldEngine/.build/clt/release"
  engine=(-D MOULD_ENGINE -I "$ENGINE_LIB" -L "$ENGINE_LIB"
          -lMouldCore -lMouldRuntime -lMouldContext -lMouldMemory -lMouldRouter -lMouldGraph -lMouldFlow -lMouldMind -lMouldMac -lMouldEngine
          -lsqlite3 -framework Network)
fi

sources=(Sources/SAVISUL/**/*.swift)
sources=(${sources:#*/AppMain.swift})
# SAVISUL Cloud and its tests, in Mould Loft's own checkout only.
cloud=()
cloud_tests=()
if [[ -d Cloud/Mac ]]; then
  cloud=(-D SAVISUL_CLOUD)
  sources+=(Cloud/Shared/*.swift Cloud/Mac/*.swift)
  cloud_tests=(Cloud/Tests/*.swift(N))
fi
frameworks=(
  -framework AppKit -framework SwiftUI -framework CoreAudio -framework AudioToolbox
  -framework IOKit -framework UserNotifications -framework ApplicationServices
  -framework ServiceManagement -framework CoreGraphics -framework Carbon
  -framework QuickLookThumbnailing -framework UniformTypeIdentifiers -framework EventKit
  -framework AVFoundation -framework ScreenCaptureKit -framework Accelerate
  -framework CoreMedia -framework CoreMediaIO -framework SpriteKit -framework CoreBluetooth -framework Photos -framework Vision
)
common=(
  -target arm64-apple-macos14.2
  -sdk "$SDK"
  -vfsoverlay "$PWD/.build/overlay.json"
  -module-cache-path "$PWD/.build/module-cache"
  -I Sources/SMCBridge/include
  -F /Library/Developer/CommandLineTools/Library/Developer/Frameworks
)

swiftc -parse-as-library -enable-testing \
  "${common[@]}" \
  "${frameworks[@]}" \
  "${engine[@]}" \
  "${cloud[@]}" \
  -module-name SAVISUL \
  -emit-module -emit-module-path .build/SAVISUL.swiftmodule \
  -emit-library -o .build/libSAVISULCheck.dylib \
  -Xlinker -install_name -Xlinker @rpath/libSAVISULCheck.dylib \
  "${sources[@]}" \
  .build/smc_bridge.o

swiftc -parse-as-library \
  "${common[@]}" \
  "${frameworks[@]}" \
  -framework Testing \
  "${engine[@]:0:4}" \
  -I .build -L .build -lSAVISULCheck \
  -Xlinker -rpath -Xlinker "$PWD/.build" \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  Tests/SAVISULTests/*.swift \
  "${cloud_tests[@]}" \
  scripts/TestMain.swift \
  -o .build/savisul-tests

exec .build/savisul-tests
