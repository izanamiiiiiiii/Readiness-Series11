#!/usr/bin/env python3
import importlib.util, json, sys, tempfile
from pathlib import Path
root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('candidate_audit', root / 'inspect-candidate.py')
audit = importlib.util.module_from_spec(spec); spec.loader.exec_module(audit)
ipa = Path(sys.argv[1]); models = json.loads((root/'models.json').read_text())
count = 0
for model in {x for values in models.values() for x in values}:
    result = audit.inspect(ipa, model, '27.3')
    assert result['packageAuditPassed'] and not result['physicalWatchCompatibilityVerified'] and not result['simulatorInstallable']
    count += 1
for model, version in [('Watch7,3', '27.2'), ('iPhone', '27.3')]:
    try: audit.inspect(ipa, model, version)
    except ValueError: count += 1
    else: raise AssertionError('Ineligible target accepted')
with tempfile.TemporaryDirectory() as folder:
    changed = Path(folder)/'changed.ipa'; changed.write_bytes(ipa.read_bytes()+b'changed')
    try: audit.inspect(changed, 'Watch7,3', '27.3')
    except ValueError: count += 1
    else: raise AssertionError('Changed package accepted')
print(f'{count} package-audit checks passed')
