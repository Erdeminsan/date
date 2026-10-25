"""Idempotent native configuration; preserves signing and unrelated URL schemes."""
import plistlib
from pathlib import Path
import xml.etree.ElementTree as ET

SCHEME = 'com.erdeminsan.playmatch'
ANDROID = '{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android', ANDROID[1:-1])


def configure(root):
    info = root / 'ios/Runner/Info.plist'
    if info.exists():
        data = plistlib.loads(info.read_bytes())
        data['CFBundleDisplayName'] = 'PlayMatch'
        data['FlutterDeepLinkingEnabled'] = False
        data['UIRequiresFullScreen'] = True
        data['UISupportedInterfaceOrientations'] = ['UIInterfaceOrientationPortrait']
        data['UISupportedInterfaceOrientations~ipad'] = ['UIInterfaceOrientationPortrait']
        schemes = data.setdefault('CFBundleURLTypes', [])
        if not any(SCHEME in item.get('CFBundleURLSchemes', []) for item in schemes):
            schemes.append({'CFBundleTypeRole': 'Editor', 'CFBundleURLSchemes': [SCHEME]})
        info.write_bytes(plistlib.dumps(data, sort_keys=False))
    manifest = root / 'android/app/src/main/AndroidManifest.xml'
    if manifest.exists():
        tree = ET.parse(manifest)
        doc = tree.getroot()
        if not any(e.get(ANDROID + 'name') == 'android.permission.INTERNET' for e in doc.findall('uses-permission')):
            ET.SubElement(doc, 'uses-permission', {ANDROID + 'name': 'android.permission.INTERNET'})
        app = doc.find('application')
        if app is None: raise ValueError('Android application missing')
        app.set(ANDROID + 'label', 'PlayMatch')
        activity = next((a for a in app.findall('activity') if a.get(ANDROID + 'name', '').endswith('MainActivity')), None)
        if activity is None: raise ValueError('MainActivity missing')
        meta = next((m for m in activity.findall('meta-data') if m.get(ANDROID + 'name') == 'flutter_deeplinking_enabled'), None)
        if meta is None: meta = ET.SubElement(activity, 'meta-data', {ANDROID + 'name': 'flutter_deeplinking_enabled'})
        meta.set(ANDROID + 'value', 'false')
        if not any(d.get(ANDROID + 'scheme') == SCHEME for f in activity.findall('intent-filter') for d in f.findall('data')):
            intent = ET.SubElement(activity, 'intent-filter')
            ET.SubElement(intent, 'action', {ANDROID + 'name': 'android.intent.action.VIEW'})
            for category in ['DEFAULT', 'BROWSABLE']:
                ET.SubElement(intent, 'category', {ANDROID + 'name': 'android.intent.category.' + category})
            ET.SubElement(intent, 'data', {ANDROID + 'scheme': SCHEME, ANDROID + 'host': 'auth-callback'})
        ET.indent(tree, space='    ')
        tree.write(manifest, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    configure(Path(__file__).resolve().parents[1])
