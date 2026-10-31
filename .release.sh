# Sourced by `ggrel <version>` (see `ggrel --help`).
# ggrel writes VERSION before running BUILD_CMD, so the DMG is named after the release version.
# Single quotes on purpose: ggrel itself substitutes ${version}.
APP_NAME="Diffr"
TEST_CMD="make test"
BUILD_CMD="make dmg"
RELEASE_ASSETS=('build/Diffr-${version}.dmg')
