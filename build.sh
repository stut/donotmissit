#!/bin/sh
# Builds DoNotMissIt.app. Install (rm first: copying over a running signed binary gets it SIGKILLed):
#   pkill -x DoNotMissIt; rm -rf /Applications/DoNotMissIt.app && cp -R DoNotMissIt.app /Applications && open /Applications/DoNotMissIt.app
set -e
cd "$(dirname "$0")"
rm -rf DoNotMissIt.app
mkdir -p DoNotMissIt.app/Contents/MacOS
swiftc -O -target arm64-apple-macos26 main.swift -o DoNotMissIt.app/Contents/MacOS/DoNotMissIt
cp Info.plist DoNotMissIt.app/Contents/
codesign --force --sign - DoNotMissIt.app
DoNotMissIt.app/Contents/MacOS/DoNotMissIt --selftest
