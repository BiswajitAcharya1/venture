#!/bin/zsh

# Preserve an explicit toolchain override and avoid changing the Mac's global
# xcode-select setting when Command Line Tools is the selected developer folder.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    venture_selected_developer="$(xcode-select -p 2>/dev/null || true)"
    if [[ -x "$venture_selected_developer/usr/bin/xcodebuild" && "$venture_selected_developer" != */CommandLineTools ]]; then
        export DEVELOPER_DIR="$venture_selected_developer"
    elif [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        print -u2 "Full Xcode is required. Install Xcode or set DEVELOPER_DIR to its Contents/Developer folder."
        exit 1
    fi
    unset venture_selected_developer
fi
