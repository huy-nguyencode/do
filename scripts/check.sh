#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swiftc -module-cache-path "$scratch/cache" Sources/Do/Task.swift Sources/Do/TaskStore.swift Checks/main.swift -o "$scratch/check"
"$scratch/check"
