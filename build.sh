#!/bin/sh
# Builds DoNotMissIt.app. Install (rm first: copying over a running signed binary gets it SIGKILLed):
#   pkill -x DoNotMissIt; rm -rf /Applications/DoNotMissIt.app && cp -R DoNotMissIt.app /Applications && open /Applications/DoNotMissIt.app
set -e
cd "$(dirname "$0")"
xcodebuild -quiet
rm -rf DoNotMissIt.app
cp -R build/Release/DoNotMissIt.app .
DoNotMissIt.app/Contents/MacOS/DoNotMissIt --selftest
