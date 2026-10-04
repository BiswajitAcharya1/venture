#!/bin/zsh

set -euo pipefail

readonly PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/tools/xcode_environment.sh"
readonly BUNDLE_IDENTIFIER="com.venture.brain-drift"

cd "$PROJECT_ROOT"

device_json="$(mktemp "${TMPDIR:-/tmp}/venture-devices.XXXXXX")"
lock_json="$(mktemp "${TMPDIR:-/tmp}/venture-lock-state.XXXXXX")"
trap 'rm -f "$device_json" "$lock_json"' EXIT
xcrun devicectl list devices --json-output "$device_json" >/dev/null

device_record="$(
    jq -r '
        .result.devices[]
        | select(.hardwareProperties.marketingName == "iPhone 13 Pro Max")
        | select(.connectionProperties.pairingState == "paired")
        | [.identifier, .hardwareProperties.udid]
        | @tsv
    ' "$device_json" | head -n 1
)"

if [[ -z "$device_record" ]]; then
    print -u2 "The paired iPhone 13 Pro Max is unavailable. Unlock it and keep it on the same network or connect USB."
    exit 1
fi

readonly DEVICE_IDENTIFIER="${device_record%%$'\t'*}"
readonly DEVICE_UDID="${device_record##*$'\t'}"

device_is_unlocked() {
    xcrun devicectl device info lockState \
        --device "$DEVICE_IDENTIFIER" \
        --json-output "$lock_json" \
        --timeout 10 >/dev/null 2>&1 || return 1
    # CoreDevice's JSON contract supplies passcodeRequired. Require an explicit
    # false value; missing/changed output must never be treated as unlocked.
    jq -e '
        [.result | .. | objects | select(has("passcodeRequired")) | .passcodeRequired]
        | length == 1 and .[0] == false
    ' "$lock_json" >/dev/null 2>&1
}

if [[ "${1:-}" == "--check" ]]; then
    if device_is_unlocked; then
        print "Ready: paired and unlocked iPhone 13 Pro Max ($DEVICE_UDID)."
    else
        print "Paired iPhone 13 Pro Max is visible, but its lock state is not ready for launching ($DEVICE_UDID)."
    fi
    exit 0
fi

print "Building Venture for iPhone 13 Pro Max..."
venture_derived_data="$(mktemp -d "${TMPDIR:-/tmp}/Venture-iPhone13ProMax.XXXXXX")"
readonly DERIVED_DATA="$venture_derived_data"
unset venture_derived_data
readonly APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/Venture.app"
source "$PROJECT_ROOT/tools/build_source_snapshot.sh"
cd "$BUILD_ROOT"
xcodebuild \
    -jobs "${VENTURE_BUILD_JOBS:-4}" \
    -project Venture.xcodeproj \
    -scheme Venture \
    -configuration Debug \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    build

print "Installing Venture..."
xcrun devicectl device install app --device "$DEVICE_IDENTIFIER" "$APP_PATH"

venture_unlock_deadline=$(( SECONDS + 60 ))
print "Venture is installed. Waiting for the iPhone to be unlocked..."
while (( SECONDS < venture_unlock_deadline )); do
    if device_is_unlocked; then
        print "Launching Venture..."
        xcrun devicectl device process launch \
            --device "$DEVICE_IDENTIFIER" \
            --terminate-existing \
            "$BUNDLE_IDENTIFIER"
        exit 0
    fi

    sleep 5
done

print -u2 "Venture is installed, but its unlocked state could not be confirmed. Unlock it and tap the Venture icon."
exit 2
