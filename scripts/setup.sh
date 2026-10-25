#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null || { echo 'Flutter PATH içinde bulunamadı. Önce Flutter SDK kurulumunu tamamlayın.'; exit 1; }
bash scripts/bootstrap_platforms.sh
flutter pub get --enforce-lockfile
dart format lib test
flutter analyze
flutter test
echo 'Kaynak kontrolleri tamamlandı. flutter run --dart-define-from-file=config/development.json ile başlatın.'
