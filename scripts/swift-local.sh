#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Some Command Line Tools installations retain a Swift 5 private manifest
# interface alongside the Swift 6 library. Repair only our local build copy.
manifest_api="$(dirname "$(xcrun --find swiftc)")/../lib/swift/pm/ManifestAPI"
public_interface="$manifest_api/PackageDescription.swiftmodule/$(uname -m)-apple-macos.swiftinterface"
private_interface="$manifest_api/PackageDescription.swiftmodule/$(uname -m)-apple-macos.private.swiftinterface"
if /usr/bin/grep -q 'swiftLanguageModes' "$public_interface" && ! /usr/bin/grep -q 'swiftLanguageModes' "$private_interface"; then
    mkdir -p .build/toolchain
    if [ ! -d .build/toolchain/ManifestAPI ]; then
        cp -R "$manifest_api" .build/toolchain/ManifestAPI
        for interface in .build/toolchain/ManifestAPI/PackageDescription.swiftmodule/*-apple-macos.swiftinterface; do
            cp "$interface" "${interface%.swiftinterface}.private.swiftinterface"
        done
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/toolchain"
fi
swift_command="$1"
shift
exec swift "$swift_command" --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security "$@"
