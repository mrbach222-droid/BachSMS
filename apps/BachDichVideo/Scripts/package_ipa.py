#!/usr/bin/env python3
"""Package a successful Xcode archive; never relabel a zip of source as an IPA."""
from pathlib import Path
import plistlib
import shutil
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / 'build/BachDichVideo.xcarchive/Products/Applications/BachDichVideo.app'
extension = app / 'PlugIns/Broadcast.appex'
for bundle in (app, extension):
    with (bundle / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    executable = bundle / info['CFBundleExecutable']
    if not executable.is_file() or executable.stat().st_size < 100:
        raise SystemExit(f'Missing built executable: {executable}')
    with executable.open('rb') as stream:
        magic = stream.read(4)
    if magic not in (bytes.fromhex('cffaedfe'), bytes.fromhex('feedfacf'),
                     bytes.fromhex('cafebabe'), bytes.fromhex('bebafeca')):
        raise SystemExit(f'Executable is not a Mach-O binary: {executable}')
    if info['CFBundleShortVersionString'] != '0.2.0':
        raise SystemExit('Version mismatch; refusing to package')
    if info['CFBundleVersion'] != '4' or 'SharedGroup' in info or 'SharedKeychainGroup' in info:
        raise SystemExit('Unexpected build number or legacy shared entitlement configuration')
    if bundle == extension and info['NSExtension'].get('RPBroadcastProcessMode') != 'RPBroadcastProcessModeSampleBuffer':
        raise SystemExit('ReplayKit sample-buffer mode is not configured')
payload = root / 'build/package/Payload'
if payload.parent.exists():
    shutil.rmtree(payload.parent)
payload.mkdir(parents=True)
shutil.copytree(app, payload / app.name, symlinks=True)
output = root / 'build/BachDichVideo_v0.2.0_UNSIGNED.ipa'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(payload.rglob('*')):
        if file.is_file():
            archive.write(file, file.relative_to(payload.parent))
print(output)
print('Unsigned build. Sign the app and its capture extension; no App Groups or shared Keychain required.')
