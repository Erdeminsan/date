import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('platforms', Path(__file__).resolve().parents[2] / 'scripts/configure_platforms.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class PlatformTests(unittest.TestCase):
    def test_configuration_is_idempotent_and_preserves_unrelated_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            info = root / 'ios/Runner/Info.plist'
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleURLTypes': [{'CFBundleURLSchemes':['existing']}], 'Unrelated': True}))
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application><activity android:name=".MainActivity"><intent-filter><action android:name="android.intent.action.MAIN"/></intent-filter></activity></application></manifest>')
            module.configure(root)
            first = (info.read_bytes(), manifest.read_bytes())
            module.configure(root)
            self.assertEqual(first, (info.read_bytes(), manifest.read_bytes()))
            data = plistlib.loads(info.read_bytes())
            self.assertTrue(data['Unrelated'])
            self.assertEqual(data['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['existing'])
            self.assertFalse(data['FlutterDeepLinkingEnabled'])
            self.assertEqual(data['CFBundleDisplayName'], 'PlayMatch')
            doc = ET.parse(manifest)
            self.assertEqual(len(doc.findall('uses-permission')), 1)
            self.assertEqual(len(doc.findall('application/activity/intent-filter')), 2)

    def test_missing_platforms_do_not_create_partial_projects(self):
        with tempfile.TemporaryDirectory() as folder:
            module.configure(Path(folder))
            self.assertEqual(list(Path(folder).iterdir()), [])
