import base64
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import signing


class SigningTests(unittest.TestCase):
    def test_tool_errors_identify_operation_and_redact_secrets_from_both_streams(self):
        env = {name: f'secret-value-{index}' for index, name in enumerate(signing.CI_SECRETS)}
        stdout = (env['ANDROID_KEYSTORE_PASSWORD'] + '\nCannot recover key').encode()
        stderr = (' '.join(env.values()) + '\nUnrecoverableKeyException').encode() + b'\xff'
        failure = subprocess.CalledProcessError(2, ['apksigner', 'sign'], output=stdout, stderr=stderr)
        with patch.object(signing.subprocess, 'run', side_effect=failure):
            with self.assertRaises(signing.SigningToolError) as caught:
                signing.run(['apksigner', 'sign'], env)
        message = str(caught.exception)
        self.assertIn('apksigner sign failed (exit 2)', message)
        self.assertIn('Cannot recover key', message)
        self.assertIn('UnrecoverableKeyException', message)
        for value in env.values():
            self.assertNotIn(value, message)

    def test_tool_errors_redact_inherited_environment(self):
        env = {'ANDROID_KEY_PASSWORD': 'private-key-password'}
        failure = subprocess.CalledProcessError(1, ['keytool', '-certreq'],
                                                output=b'private-key-password')
        with patch.dict(os.environ, env, clear=True):
            with patch.object(signing.subprocess, 'run', side_effect=failure):
                with self.assertRaises(signing.SigningToolError) as caught:
                    signing.run(['keytool', '-certreq'])
        self.assertNotIn(env['ANDROID_KEY_PASSWORD'], str(caught.exception))
        self.assertIn('keytool -certreq', str(caught.exception))

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

    def test_configure_checks_private_key_before_rewriting_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            key = root / 'release.jks'
            key.write_bytes(b'existing keystore')
            private = root / 'signing-secrets.properties'
            private.write_text(signing.properties_text({
                'storeFile': key.name, 'storePassword': 'store-password',
                'keyAlias': 'release', 'keyPassword': 'wrong-key-password',
            }), encoding='utf-8')
            android = root / 'key.properties'
            android.write_text('original configuration', encoding='utf-8')
            export = root / 'release.jks.base64'
            export.write_text('original export', encoding='ascii')
            with patch.multiple(signing, KEYSTORE=key, PRIVATE_CONFIG=private,
                                ANDROID_CONFIG=android, BASE64_EXPORT=export):
                with patch.object(signing, 'keytool', return_value='keytool'):
                    with patch.object(signing, 'run', side_effect=[b'certificate',
                                      signing.SigningToolError('Cannot recover key')]):
                        with self.assertRaisesRegex(signing.SigningToolError, 'Cannot recover key'):
                            signing.configure()
            self.assertEqual(android.read_text(), 'original configuration')
            self.assertEqual(export.read_text(), 'original export')
            self.assertEqual(key.read_bytes(), b'existing keystore')

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

    def test_ci_wrong_private_key_password_is_actionable_and_never_publishes(self):
        env = {'ANDROID_KEYSTORE_BASE64': base64.b64encode(b'keystore').decode(),
               'ANDROID_KEYSTORE_PASSWORD': 'store-password', 'ANDROID_KEY_ALIAS': 'release',
               'ANDROID_KEY_PASSWORD': 'wrong-private-password',
               'RELEASE_VERSION_NAME': '1.2.0', 'RELEASE_VERSION_CODE': '4'}

        def tool(arguments, **kwargs):
            if arguments[1] == 'dump':
                return SimpleNamespace(stdout=b"package: name='io.github.yuuge7.companion' "
                                       b"versionCode='4' versionName='1.2.0'\n")
            if arguments[1] == '-exportcert':
                return SimpleNamespace(stdout=b'certificate')
            self.assertEqual(arguments[1], 'sign')
            raise subprocess.CalledProcessError(2, arguments,
                  stderr=b'UnrecoverableKeyException: Cannot recover key wrong-private-password')

        with tempfile.TemporaryDirectory() as temporary:
            env['RUNNER_TEMP'] = temporary
            destination = Path(temporary) / 'dist' / 'output.apk'
            with patch.dict(os.environ, env, clear=True):
                with patch.object(signing, 'android_tool', side_effect=lambda name: name):
                    with patch.object(signing, 'keytool', return_value='keytool'):
                        with patch.object(signing.subprocess, 'run', side_effect=tool):
                            with self.assertRaises(ValueError) as caught:
                                signing.sign_ci(Path('app.apk'), destination)
            message = str(caught.exception)
            self.assertIn('ANDROID_KEY_PASSWORD does not unlock', message)
            self.assertIn('keyPassword value from signing-secrets.properties', message)
            self.assertIn('apksigner sign failed (exit 2)', message)
            self.assertNotIn(env['ANDROID_KEY_PASSWORD'], message)
            self.assertFalse(destination.exists())
            self.assertEqual(list(Path(temporary).iterdir()), [destination.parent])

    def test_ci_invalid_base64_reports_the_secret_name(self):
        env = {name: 'not-base64!' for name in signing.CI_SECRETS}
        env.update(RELEASE_VERSION_NAME='1.2.0', RELEASE_VERSION_CODE='4')
        with tempfile.TemporaryDirectory() as temporary:
            with patch.dict(os.environ, env, clear=True):
                with patch.object(signing, 'validate_apk'):
                    with self.assertRaisesRegex(ValueError, 'ANDROID_KEYSTORE_BASE64 must contain'):
                        signing.sign_ci(Path('app.apk'), Path(temporary) / 'output.apk')

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
