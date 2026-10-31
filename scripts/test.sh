#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

sdk_path="$(xcrun --show-sdk-path 2>/dev/null || true)"
if [[ -z "$sdk_path" ]]; then
    printf '%s\n' "Error: Failed to locate macOS SDK via xcrun" >&2
    exit 1
fi

# Private, unpredictable directory: a guessable /tmp path could be pre-planted or swapped
# by another local user between compiling and executing the test binary.
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/RunSwiftTests.XXXXXX")"
test_bin="${test_dir}/RunSwiftTests"
trap 'rm -rf "$test_dir"' EXIT INT TERM

# Collect app sources excluding entry points with @main (e.g. Main.swift)
sources=()
while IFS= read -r file; do
    if ! grep -q "@main" "$file" 2>/dev/null; then
        sources+=("$file")
    fi
done < <(find Sources/App -type f -name "*.swift" | sort)

# Collect test sources
tests=()
while IFS= read -r file; do
    tests+=("$file")
done < <(find Tests -type f -name "*.swift" | sort)

if [[ ${#tests[@]} -eq 0 ]]; then
    printf '%s\n' "Error: No test files found under Tests" >&2
    exit 1
fi

printf '%s\n' "Compiling unit test suite..."
swiftc -sdk "$sdk_path" \
    "${sources[@]}" \
    "${tests[@]}" \
    -o "$test_bin"

test_status=0
"$test_bin" || test_status=$?

if [[ "$test_status" -ne 0 ]]; then
    printf '%s\n' "Error: Swift unit tests failed with status ${test_status}" >&2
    exit "$test_status"
fi
