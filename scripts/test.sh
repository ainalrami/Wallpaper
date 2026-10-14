#!/bin/sh
# Builds every target and runs the test suite. Used by the pre-commit hook.
set -eu
cd "$(dirname "$0")/.."
swiftly run swift build
swiftly run swift test
