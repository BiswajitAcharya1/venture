#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Venture.xcodeproj/project.pbxproj"
MODELS="$ROOT/Venture/Resources/Models"
failed=0

check_file() {
  path="$1"
  label="$2"
  if [ ! -s "$path" ]; then
    printf 'error: %s is missing or empty: %s\n' "$label" "$path" >&2
    failed=1
  fi
}

check_file "$MODELS/SileroVAD.mlpackage/Manifest.json" "Silero VAD manifest"
check_file "$MODELS/SileroVAD.mlpackage/Data/com.apple.CoreML/weights/weight.bin" "Silero VAD weights"

for reference in $(sed -n 's/.*path = \(Resources\/Models\/[^;]*\);.*/\1/p' "$PROJECT"); do
  artifact="$ROOT/Venture/$reference"
  case "$artifact" in
    *.mlpackage)
      check_file "$artifact/Manifest.json" "referenced Core ML package"
      ;;
    *)
      check_file "$artifact" "referenced model resource"
      ;;
  esac
done

if [ "$failed" -ne 0 ]; then
  printf 'Model artifact verification failed. Do not archive this build.\n' >&2
  exit 1
fi

printf 'Model artifacts verified. No empty referenced model resources found.\n'
