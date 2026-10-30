import importlib.util
import io
import json
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('updater', Path(__file__).resolve().parents[1] / 'Sources' / 'updater.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)

class UpdateTests(unittest.TestCase):
    def test_versions(self):
        self.assertTrue(u.is_newer('v0.10.0', '0.2.0'))
        self.assertFalse(u.is_newer('v0.2.0', '0.2.0'))
        self.assertFalse(u.is_newer('v0.1.9', '0.2.0'))
        with self.assertRaises(ValueError): u.is_newer('v1.0.0-rc1', '0.2.0')

    def test_selects_only_expected_verified_release_asset(self):
        asset = {'name': 'Warp-Voice.zip', 'browser_download_url': 'https://github.com/dovudo/warp-voice/releases/download/v1.0.0/Warp-Voice.zip', 'digest': 'sha256:' + 'a'*64, 'size': 100}
        self.assertEqual(u.release_info({'tag_name':'v1.0.0','assets':[asset]}, '0.2.0')['version'], '1.0.0')
        asset['browser_download_url'] = 'https://evil.example/a.zip'
        with self.assertRaises(ValueError): u.release_info({'tag_name':'v1.0.0','assets':[asset]}, '0.2.0')

    def test_rejects_zip_traversal_and_symlinks(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'bad.zip'
            with zipfile.ZipFile(p,'w') as z: z.writestr('../evil', 'x')
            with self.assertRaises(ValueError): u.unpack(p,Path(d)/'out')

    def test_restores_original_when_installation_fails(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); old=root/'Warp Voice.app'; old.mkdir(); (old/'old').write_text('old')
            missing=root/'missing.app'
            with self.assertRaises(OSError): u.swap_app(old,missing,root/'backup.app')
            self.assertEqual((old/'old').read_text(),'old')

    def test_restores_previous_version_if_launch_fails(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); old=root/'Warp Voice.app'; old.mkdir(); (old/'old').write_text('old')
            staged=root/'new.app'; staged.mkdir(); (staged/'new').write_text('new')
            with patch.object(u.os, 'kill', side_effect=ProcessLookupError), patch.object(u.subprocess, 'run', side_effect=[OSError('launch failed'), None]):
                with self.assertRaises(OSError): u.apply_update(old,staged,root/'backup.app',999999)
            self.assertEqual((old/'old').read_text(),'old')

if __name__ == '__main__': unittest.main()
