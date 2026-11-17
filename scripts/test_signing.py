import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import signing


class SigningTests(unittest.TestCase):
    def test_generate_never_replaces_existing_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            key = Path(temporary) / 'release.jks'
            key.write_bytes(b'original identity')
            with patch.object(signing, 'KEYSTORE', key):
                with self.assertRaisesRegex(ValueError, 'Refusing to replace'):
                    signing.generate()
            self.assertEqual(key.read_bytes(), b'original identity')

    def test_configure_requires_original_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(signing, 'KEYSTORE', Path(temporary) / 'missing.jks'):
                with self.assertRaisesRegex(ValueError, 'Restore'):
                    signing.configure()

    def test_metadata_rejects_wrong_package_version_and_debuggable_apks(self):
        valid = "package: name='io.github.yuuge7.companion' versionCode='4' versionName='1.2.0'\n"
        with patch.object(signing, 'android_tool', return_value='aapt'):
            with patch.object(signing, 'run', return_value=valid.encode()):
                signing.validate_apk(Path('app.apk'), '1.2.0', '4')
                with self.assertRaisesRegex(ValueError, 'package/version'):
                    signing.validate_apk(Path('app.apk'), '1.3.0', '5')
            with patch.object(signing, 'run', return_value=(valid + 'application-debuggable\n').encode()):
                with self.assertRaisesRegex(ValueError, 'debuggable'):
                    signing.validate_apk(Path('app.apk'), '1.2.0', '4')

    def test_signing_requires_all_four_secrets(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'ANDROID_KEYSTORE_BASE64'):
                signing.sign_ci(Path('app.apk'), Path('output.apk'))

    def test_certificate_verification_handles_windows_and_unix_line_endings(self):
        digest = 'a' * 64
        with patch.object(signing, 'android_tool', return_value='apksigner'):
            for newline in ('\n', '\r\n'):
                output = f'Signer #1 certificate SHA-256 digest: {digest}{newline}'
                with patch.object(signing, 'run', return_value=output.encode()):
                    signing.verify_signed_apk(Path('app.apk'), digest)
                    with self.assertRaisesRegex(ValueError, 'certificate'):
                        signing.verify_signed_apk(Path('app.apk'), 'b' * 64)
                with patch.object(signing, 'run', return_value=(output + 'CN=Android Debug').encode()):
                    with self.assertRaisesRegex(ValueError, 'certificate'):
                        signing.verify_signed_apk(Path('app.apk'), digest)


if __name__ == '__main__':
    unittest.main()
