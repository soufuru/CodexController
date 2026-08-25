#!/bin/zsh
set -eu

script_directory="${0:A:h}"
cd "$script_directory/CodexBridge"

# SwiftPM's incremental build is fast and guarantees that source changes are
# reflected in the process this script launches.
swift build

echo "CodexBridge Desktop shared mode"
echo "Keep this Terminal window open. Press Control-C to stop."
CODEX_DESKTOP_SHARED=1 .build/debug/CodexBridge
