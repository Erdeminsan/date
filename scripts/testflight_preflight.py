"""Read-only host checks. Does not upload, sign, or read signing credentials."""
import json
import platform
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def command(args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()
    except (OSError, subprocess.CalledProcessError):
        return ''


def major(output):
    match = re.search(r'(\d+)\.', output)
    return int(match.group(1)) if match else 0


def main():
    failures = []
    if platform.system() != 'Darwin': failures.append('İmzalı iOS arşivi için macOS gerekir.')
    xcode = command(['xcodebuild', '-version'])
    if major(xcode) < 26: failures.append('Xcode 26 veya üstünü kurup xcode-select ile seç.')
    sdk = command(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'])
    if major(sdk) < 26: failures.append('Seçili Xcode iOS 26 SDK veya üstünü içermeli.')
    flutter = command(['flutter', '--version', '--machine'])
    try:
        version = json.loads(flutter)['frameworkVersion']
        if tuple(map(int, version.split('.')[:2])) < (3, 38):
            failures.append('Xcode 26 için Flutter en az 3.38 olmalı. CI sürümü: 3.38.0.')
    except (ValueError, KeyError, TypeError): failures.append('Flutter sürümü okunamadı.')
    for file in ['pubspec.lock', 'ios/Runner.xcworkspace/contents.xcworkspacedata']:
        if not (ROOT / file).exists(): failures.append(f'{file} eksik; önce bash scripts/setup.sh çalıştır.')
    print(xcode or 'Xcode bulunamadı.')
    print('iOS SDK:', sdk or 'bulunamadı')
    for failure in failures: print('EKSİK:', failure)
    if failures: return 1
    print('Yerel araç kontrolleri geçti. Bu sonuç imzalama, SMTP veya App Store Connect onayı değildir.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
