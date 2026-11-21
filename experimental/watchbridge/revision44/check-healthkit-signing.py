#!/usr/bin/env python3
"""macOS: audit a SIGNED WatchBridge IPA without printing account/device IDs."""
import argparse,json,pathlib,plistlib,subprocess,tempfile,zipfile
p=argparse.ArgumentParser();p.add_argument('ipa',type=pathlib.Path);a=p.parse_args()
results=[]
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp).resolve()
 with zipfile.ZipFile(a.ipa) as z:
  for item in z.infolist():
   target=(root/item.filename).resolve()
   if not target.is_relative_to(root): raise SystemExit('Unsafe archive path')
  z.extractall(root)
 for app in (root/'Payload').glob('*.app/Watch/*.app'):
  info=plistlib.loads((app/'Info.plist').read_bytes());profile=app/'embedded.mobileprovision'
  signature=subprocess.run(['codesign','-d','--entitlements',':-',str(app)],capture_output=True)
  data=signature.stdout
  try: ent=plistlib.loads(data[data.index(b'<?xml'):])
  except (ValueError,plistlib.InvalidFileException): ent={}
  pe={}
  if profile.exists():
   r=subprocess.run(['security','cms','-D','-i',str(profile)],capture_output=True)
   if r.returncode==0: pe=plistlib.loads(r.stdout).get('Entitlements',{})
  results.append({'healthUsageDescriptionPresent':bool(info.get('NSHealthShareUsageDescription')),
   'signatureGrantsHealthKit':ent.get('com.apple.developer.healthkit') is True,
   'profileGrantsHealthKit':pe.get('com.apple.developer.healthkit') is True})
print(json.dumps({'watchApps':results,'passes':bool(results) and all(all(x.values()) for x in results)},indent=2))
raise SystemExit(0 if results and all(all(x.values()) for x in results) else 1)
