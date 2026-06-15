#!/bin/sh
# Xcode Cloud runs this before building (must live in ci_scripts/ at repo root, executable).
# Syncs the TestFlight build's marketing version with the git tag.

set -e

if [ -n "$CI_TAG" ]; then
  VERSION="${CI_TAG#v}"
  echo "Setting marketing version to $VERSION from tag $CI_TAG"
  cd "$CI_PRIMARY_REPOSITORY_PATH"
  agvtool new-marketing-version "$VERSION"
else
  echo "No CI_TAG set — leaving marketing version untouched."
fi
