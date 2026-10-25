#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null || { echo 'Flutter PATH içinde bulunamadı. Önce Flutter SDK kurulumunu tamamlayın.'; exit 1; }
if [ ! -d ios ]; then
  scaffold_dir="$(mktemp -d)"
  trap 'rm -rf "$scaffold_dir"' EXIT
  flutter create --no-pub --platforms=ios,android --org com.erdeminsan --project-name playmatch "$scaffold_dir/playmatch"
  cp -R "$scaffold_dir/playmatch/ios" ./ios
  cp -R "$scaffold_dir/playmatch/android" ./android
  cp "$scaffold_dir/playmatch/.metadata" ./.metadata
fi
flutter pub get
dart format lib test
flutter analyze
flutter test
echo 'Kaynak kontrolleri tamamlandı. flutter run ile cihazda deneyin.'
