"""Manage Companion's permanent local signing key and sign CI APKs."""

import base64
import hashlib
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
KEYSTORE = ROOT / 'companion-release.jks'
PRIVATE_CONFIG = ROOT / 'signing-secrets.properties'
ANDROID_CONFIG = ROOT / 'android/key.properties'
BASE64_EXPORT = ROOT / 'companion-release.jks.base64'


def keytool():
    java_home = os.environ.get('JAVA_HOME')
    candidate = Path(java_home) / 'bin' / ('keytool.exe' if os.name == 'nt' else 'keytool') if java_home else None
    if candidate and candidate.is_file():
        return str(candidate)
    executable = shutil.which('keytool')
    if not executable:
        raise ValueError('Install a JDK and put keytool on PATH, or set JAVA_HOME.')
    return executable


def run(arguments, env=None):
    # Signing commands never include passwords in their arguments or output.
    return subprocess.run(arguments, env=env, check=True, capture_output=True).stdout


def load_properties(file):
    return dict(line.split('=', 1) for line in file.read_text(encoding='utf-8').splitlines()
                if line and not line.startswith('#'))


def properties_text(config):
    return ''.join(f'{name}={config[name]}\n' for name in ('storeFile', 'storePassword', 'keyAlias', 'keyPassword'))


def signing_env(config):
    return {**os.environ, 'ANDROID_KEYSTORE_PASSWORD': config['storePassword'],
            'ANDROID_KEY_PASSWORD': config['keyPassword']}


def fingerprint(keystore, alias, env):
    certificate = run([keytool(), '-exportcert', '-keystore', str(keystore),
                       '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD', '-alias', alias], env)
    return hashlib.sha256(certificate).hexdigest()


def configure():
    if not KEYSTORE.is_file() or not PRIVATE_CONFIG.is_file():
        raise ValueError('Restore companion-release.jks and signing-secrets.properties to the project root first.')
    config = load_properties(PRIVATE_CONFIG)
    expected = fingerprint(KEYSTORE, config['keyAlias'], signing_env(config))
    config['storeFile'] = KEYSTORE.name
    ANDROID_CONFIG.write_text(properties_text(config), encoding='utf-8')
    BASE64_EXPORT.write_text(base64.b64encode(KEYSTORE.read_bytes()).decode('ascii'), encoding='ascii')
    print(f'Configured permanent signing identity. Certificate SHA-256: {expected}')


def generate():
    for file in (KEYSTORE, PRIVATE_CONFIG, ANDROID_CONFIG, BASE64_EXPORT):
        if file.exists():
            raise ValueError(f'{file.name} already exists. Refusing to replace a signing identity.')
    config = {'storeFile': KEYSTORE.name, 'keyAlias': 'companion',
              'storePassword': secrets.token_urlsafe(32), 'keyPassword': secrets.token_urlsafe(32)}
    run([keytool(), '-genkeypair', '-noprompt', '-storetype', 'JKS',
         '-keystore', str(KEYSTORE), '-alias', config['keyAlias'], '-keyalg', 'RSA',
         '-keysize', '3072', '-validity', '10000', '-dname', 'CN=Companion, OU=Android, O=Companion',
         '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD', '-keypass:env', 'ANDROID_KEY_PASSWORD'], signing_env(config))
    with PRIVATE_CONFIG.open('x', encoding='utf-8') as file:
        file.write(properties_text(config))
    configure()
    print('Created companion-release.jks and signing-secrets.properties. Back up both private files securely.')


def android_tool(name):
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise ValueError('Set ANDROID_HOME to the Android SDK directory.')
    suffix = '.bat' if os.name == 'nt' and name == 'apksigner' else '.exe' if os.name == 'nt' else ''
    file = Path(sdk) / 'build-tools/36.0.0' / f'{name}{suffix}'
    if not file.is_file():
        raise ValueError(f'Install Android SDK build-tools 36.0.0 (missing {name}).')
    return str(file)


def validate_apk(apk, version_name, version_code):
    badging = run([android_tool('aapt'), 'dump', 'badging', str(apk)]).decode('utf-8')
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != ('io.github.yuuge7.companion', str(version_code), version_name):
        raise ValueError('APK package/version does not match the trusted release plan.')
    if 'application-debuggable' in badging:
        raise ValueError('Refusing to publish a debuggable APK.')


def verify_signed_apk(apk, expected):
    verification = run([android_tool('apksigner'), 'verify', '--verbose', '--print-certs', str(apk)]).decode('utf-8')
    actual = re.search(r'^Signer #1 certificate SHA-256 digest: ([a-f0-9]{64})\r?$', verification, re.M)
    if not actual or actual.group(1) != expected or 'CN=Android Debug' in verification:
        raise ValueError('APK certificate does not match the permanent release key.')


def sign_ci(apk, destination):
    names = ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD')
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise ValueError('Configure repository Actions secrets: ' + ', '.join(missing))
    validate_apk(apk, os.environ['RELEASE_VERSION_NAME'], os.environ['RELEASE_VERSION_CODE'])
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise ValueError('Output APK already exists; refusing to overwrite it.')
    encoded = ''.join(os.environ['ANDROID_KEYSTORE_BASE64'].split())
    key_bytes = base64.b64decode(encoded, validate=True)
    with tempfile.TemporaryDirectory(prefix='companion-signing-', dir=os.environ.get('RUNNER_TEMP')) as temporary:
        keystore = Path(temporary) / KEYSTORE.name
        keystore.write_bytes(key_bytes)
        alias = os.environ['ANDROID_KEY_ALIAS']
        expected = fingerprint(keystore, alias, os.environ)
        signer = android_tool('apksigner')
        signed_apk = Path(temporary) / 'signed.apk'
        run([signer, 'sign', '--ks', str(keystore), '--ks-key-alias', alias,
             '--ks-pass', 'env:ANDROID_KEYSTORE_PASSWORD', '--key-pass', 'env:ANDROID_KEY_PASSWORD',
             '--v4-signing-enabled', 'false', '--out', str(signed_apk), str(apk)])
        verify_signed_apk(signed_apk, expected)
        with signed_apk.open('rb') as source, destination.open('xb') as target:
            shutil.copyfileobj(source, target)
        print(f'Signed and verified {destination.name}. Certificate SHA-256: {expected}')


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['generate']:
            generate()
        elif sys.argv[1:] == ['configure']:
            configure()
        elif len(sys.argv) == 4 and sys.argv[1] == 'sign-ci':
            sign_ci(Path(sys.argv[2]), Path(sys.argv[3]))
        else:
            raise ValueError('Usage: python scripts/signing.py generate | configure | sign-ci INPUT.apk OUTPUT.apk')
    except subprocess.CalledProcessError as error:
        print(f'Signing tool failed (exit {error.returncode}). Check the keystore, alias and passwords.', file=sys.stderr)
        sys.exit(1)
    except (ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
