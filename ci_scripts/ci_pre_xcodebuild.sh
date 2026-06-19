#!/bin/sh
# Xcode Cloud runs this before building (must live in ci_scripts/ at repo root, executable).
# Syncs the build's marketing version with the git tag.
#
# agvtool is unusable here: it does not update the MARKETING_VERSION build setting
# and aborts with "Cannot find .../YES" on targets that set GENERATE_INFOPLIST_FILE=YES
# without an INFOPLIST_FILE. MARKETING_VERSION is defined once at the project level
# (the app and widget extension inherit it), so set it directly in the project file.

set -e

if [ -n "$CI_TAG" ]; then
  VERSION="${CI_TAG#v}"
  echo "Setting marketing version to $VERSION from tag $CI_TAG"
  cd "$CI_PRIMARY_REPOSITORY_PATH"
  /usr/bin/sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${VERSION};/g" Cassette.xcodeproj/project.pbxproj
else
  echo "No CI_TAG set — leaving marketing version untouched."
fi
