#!/bin/bash
# Builds the app's pure decision logic together with Tests/*.swift and runs the checks. No XCTest needed.
set -euo pipefail
cd "$(dirname "$0")/.."

# Only files with no AppKit or IOKit, so the checks build into a small command line tool.
sources=(Sources/TabPulse/AwakePolicy.swift Sources/TabPulse/Attention.swift Sources/TabPulse/Session.swift)
OBJ=.build/logic-tests
flags=(-Onone -swift-version 5 -parse-as-library)

# The same stale SwiftBridging module map workaround as build.sh.
clt=/Library/Developer/CommandLineTools/usr/include/swift
mkdir -p "$OBJ"
if [ -f "$clt/bridging.modulemap" ] && grep -qs "SwiftBridging" "$clt/module.modulemap"; then
  : >"$OBJ/empty.modulemap"
  printf '{"version":0,"case-sensitive":"false","roots":[{"type":"file","name":"%s","external-contents":"%s"}]}\n' \
    "$clt/module.modulemap" "$PWD/$OBJ/empty.modulemap" >"$OBJ/overlay.yaml"
  flags+=(-vfsoverlay "$OBJ/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$OBJ/overlay.yaml")
fi

swiftc "${flags[@]}" -target "$(uname -m)-apple-macos14.0" -o "$OBJ/LogicTests" "${sources[@]}" Tests/*.swift
"$OBJ/LogicTests"
