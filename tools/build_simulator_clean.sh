#!/bin/zsh

set -euo pipefail

readonly PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/tools/xcode_environment.sh"
venture_derived_data="$(mktemp -d "${TMPDIR:-/tmp}/venture-derived-data.XXXXXX")"
readonly DERIVED_DATA="$venture_derived_data"
unset venture_derived_data
print "Derived data: $DERIVED_DATA"
source "$PROJECT_ROOT/tools/build_source_snapshot.sh"

cd "$BUILD_ROOT"

xcodebuild \
    -jobs "${VENTURE_BUILD_JOBS:-4}" \
    -project Venture.xcodeproj \
    -scheme Venture \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build
