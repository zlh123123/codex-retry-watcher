#!/bin/bash
# Renders AppIcon.icns from MakeIcon.swift.
set -euo pipefail
cd "$(dirname "$0")"

swiftc -O MakeIcon.swift -o ./makeicon
rm -rf AppIcon.iconset
./makeicon
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset ./makeicon
echo "wrote $(pwd)/AppIcon.icns"
