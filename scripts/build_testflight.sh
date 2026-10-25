#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_number="${1:-}"
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo 'Kullanım: bash scripts/build_testflight.sh <yeni-build-numarası>'
  exit 1
fi
python3 scripts/testflight_preflight.py
flutter analyze
flutter test
# Bundle identifier and Team must already be set in Xcode. This creates an
# archive/IPA locally; it never uploads or distributes a build.
flutter build ipa --release --build-number="$build_number" --dart-define-from-file=config/development.json
echo 'Arşiv: build/ios/archive/Runner.xcarchive. Xcode Organizer ile Validate App, ardından Distribute App.'
