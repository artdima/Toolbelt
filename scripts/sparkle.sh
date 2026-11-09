#!/bin/sh
# Runs one of Sparkle's tools (generate_keys, sign_update) from the package the
# project resolves into build/SourcePackages, so it matches the framework in the app.
# Usage: sparkle.sh <tool> [arguments]
set -eu

if [ $# -eq 0 ]; then
    echo "usage: $(basename "$0") <tool> [arguments]" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
packages=$root/build/SourcePackages
name=$1
shift

find_tool() {
    find "$packages/artifacts" -type f -path "*/Sparkle/bin/$name" 2>/dev/null | head -n 1
}

tool=$(find_tool)
if [ -z "$tool" ]; then
    xcodebuild -resolvePackageDependencies -quiet -project "$root/Toolbelt.xcodeproj" \
        -clonedSourcePackagesDirPath "$packages" >&2
    tool=$(find_tool)
fi
if [ -z "$tool" ]; then
    echo "error: the Sparkle package has no tool $name" >&2
    exit 1
fi
exec "$tool" "$@"
