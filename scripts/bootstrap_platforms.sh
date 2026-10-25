#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null || { echo 'Flutter PATH içinde bulunamadı.'; exit 1; }
if [ ! -d ios ] || [ ! -d android ]; then
  scaffold_dir="$(mktemp -d)"
  trap 'rm -rf "$scaffold_dir"' EXIT
  flutter create --no-pub --platforms=ios,android --org com.erdeminsan --project-name playmatch "$scaffold_dir/playmatch"
  if [ ! -d ios ]; then cp -R "$scaffold_dir/playmatch/ios" ./ios; fi
  if [ ! -d android ]; then cp -R "$scaffold_dir/playmatch/android" ./android; fi
  if [ ! -f .metadata ]; then cp "$scaffold_dir/playmatch/.metadata" ./.metadata; fi
fi
python3 scripts/configure_platforms.py
