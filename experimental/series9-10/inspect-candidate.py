#!/usr/bin/env python3
"""Read-only package audit. Passing this audit is not a device compatibility test."""
import argparse, hashlib, json, plistlib, struct, zipfile
from pathlib import Path
BASELINE_SHA256 = 'e75de7151ad544abd73da0345a9696e00d463e38abf2eb1738fd2acc402ad2de'
def inspect(path, model, watchos):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != BASELINE_SHA256:
        raise ValueError('Package differs from the audited build42 baseline; inspect a new baseline before using this audit')
    models = json.loads(Path(__file__).with_name('models.json').read_text())
    targets = {identifier for values in models.values() for identifier in values}
    if model not in targets:
        raise ValueError('Target identifier is outside the experimental Series 9/10 scope')
    def macho(blob):
        if blob[:4] != b'\xcf\xfa\xed\xfe': raise ValueError('Expected thin little-endian Mach-O 64')
        cpu, subtype, _, count = struct.unpack_from('<IIII', blob, 4)
        if cpu != 0x100000c: raise ValueError('Expected ARM64 CPU family')
        commands = []; offset = 32
        for _ in range(count):
            kind, size = struct.unpack_from('<II', blob, offset)
            if size < 8 or offset + size > len(blob): raise ValueError('Invalid load command')
            if kind == 0x32:
                platform, minimum, sdk = struct.unpack_from('<III', blob, offset + 8)
                commands.append({'platform': platform, 'minimumOS': f'{minimum >> 16}.{(minimum >> 8) & 255}.{minimum & 255}'})
            offset += size
        if not commands or any(x['platform'] != 4 for x in commands):
            raise ValueError('Package must target physical watchOS, not Simulator')
        return {'cpu': 'arm64e' if subtype & 0xffffff == 2 else 'arm64', 'subtypeHex': hex(subtype), 'buildVersions': commands}
    with zipfile.ZipFile(path) as z:
        if z.testzip() is not None: raise ValueError('Damaged ZIP')
        names = z.namelist()
        if any('embedded.mobileprovision' in n or '/Documents/' in n for n in names):
            raise ValueError('Unexpected provisioning or device data in public candidate')
        info = plistlib.loads(z.read('Payload/Readiness.app/Info.plist'))
        binaries = {name: macho(z.read(name)) for name in names if name.endswith(('/Cobalt', '/ReadinessBridge', '/Fit'))}
    if len(binaries) != 3: raise ValueError('Expected Cobalt, ReadinessBridge and Fit')
    version = tuple(int(x) for x in watchos.split('.'))
    if (version + (0, 0))[:3] < (27, 3, 0):
        raise ValueError('Recovered candidate requires watchOS 27.3 or later; do not lower its deployment target')
    return {'status': 'experimental-unverified', 'packageAuditPassed': True, 'physicalWatchCompatibilityVerified': False,
            'targetModel': model, 'reportedWatchOS': watchos, 'validatedBaselineOS': '27.3 beta 2 (24S5296d), Series 11 only',
            'watchOSBuildMatchVerified': False, 'simulatorInstallable': False,
            'bundle': info['CFBundleIdentifier'], 'build': info['CFBundleVersion'], 'sha256': BASELINE_SHA256, 'binaries': binaries}
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path); parser.add_argument('--model', required=True); parser.add_argument('--watchos', required=True)
    args = parser.parse_args()
    try: print(json.dumps(inspect(args.ipa, args.model, args.watchos), indent=2))
    except (ValueError, KeyError, OSError, struct.error, zipfile.BadZipFile) as error: parser.exit(1, f'Audit failed: {error}\n')
