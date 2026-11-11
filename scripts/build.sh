#!/bin/sh
# Build Ember. Usage: scripts/build.sh [Debug|Release] [--install]
#   --install  copy the built app to /Applications and (re)launch it.
set -eu

cd "$(dirname "$0")/.."
configuration="${1:-Release}"
install=false
[ "${2:-}" = "--install" ] && install=true

(cd EmberCore && swift test --quiet)
mise exec -- xcodegen generate --quiet
xcodebuild \
    -project Ember.xcodeproj \
    -scheme Ember \
    -configuration "$configuration" \
    -derivedDataPath build/DerivedData \
    build -quiet

app="build/DerivedData/Build/Products/$configuration/Ember.app"
echo "Built $app"

if $install; then
    pkill -x Ember 2>/dev/null && sleep 1 || true
    rm -rf /Applications/Ember.app
    cp -R "$app" /Applications/
    open /Applications/Ember.app
    echo "Installed and launched /Applications/Ember.app"
fi
