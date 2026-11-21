#!/usr/bin/env python3
import argparse,hashlib,plistlib,shutil,struct,subprocess,zipfile,os,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--base-ipa',type=Path,required=True);a=p.parse_args()

r=Path(__file__).resolve().parent; original=a.base_ipa.resolve()
assert hashlib.sha256(original.read_bytes()).hexdigest()=='e75de7151ad544abd73da0345a9696e00d463e38abf2eb1738fd2acc402ad2de'
build=r/'build-generic';build.mkdir(exist_ok=True)
with zipfile.ZipFile(original) as z:z.extractall(build/'input')
host=build/'Payload/ReadinessHost.app';watch=host/'Watch/Readiness.app';watch.parent.mkdir(parents=True,exist_ok=True);shutil.copytree(build/'input/Payload/Readiness.app',watch,dirs_exist_ok=True)
hostid='cl.moises.Readiness';watchid=hostid+'.watchkitapp';signedid=None
bridge=watch/'Frameworks/ReadinessBridge.framework/ReadinessBridge'
b=bytearray(bridge.read_bytes())
# The recovered bridge's own bundle-name guard is not portable across signing
# tools. Remove ONLY that guard, retaining its Cobalt-specific integration.
# The package hash and exact original instructions are checked before patching.
# This is not an entitlement or platform security check; no HealthKit permission
# is added. This bridge is packaged only in the known recovered Cobalt app.
site=0xDA9B4
assert b[site:site+4] == bytes.fromhex('60000037'), 'Unexpected bridge guard instruction'
assert b[site+4:site+12] == bytes.fromhex('010000141f010014'), 'Unexpected bridge guard fallback'
# Unconditionally enter the existing setup block at +12 instead of rejecting
# the same app when WatchBridge changes its CFBundleIdentifier during signing.
b[site:site+4]=bytes.fromhex('03000014')
bridge.write_bytes(b)
d=plistlib.loads((watch/'Info.plist').read_bytes());d['CFBundleIdentifier']=watchid;d['WKCompanionAppBundleIdentifier']=hostid;d.pop('WKWatchOnly',None);(watch/'Info.plist').write_bytes(plistlib.dumps(d))
info={'CFBundleIdentifier':hostid,'CFBundleExecutable':'ReadinessHost','CFBundleName':'ReadinessHost','CFBundleDisplayName':'Readiness Host','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'44','MinimumOSVersion':'17.0','UIDeviceFamily':[1,2],'CFBundleSupportedPlatforms':['iPhoneOS'],'LSRequiresIPhoneOS':True,'UILaunchScreen':{}}
info['UIApplicationSceneManifest']={'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Readiness','UISceneDelegateClassName':'ReadinessSceneDelegate'}]}}
(host/'Info.plist').write_bytes(plistlib.dumps(info))
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer');sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],env=env,text=True).strip()
subprocess.run(['xcrun','clang','-target','arm64-apple-ios17.0','-isysroot',sdk,'-fobjc-arc',str(r/'Sources/main.m'),'-framework','UIKit','-framework','Foundation','-o',str(host/'ReadinessHost')],env=env,check=True)
for binary in [watch/'Cobalt',bridge,watch/'Frameworks/Fit.framework/Fit']:
 subprocess.run(['codesign','--remove-signature',str(binary)],capture_output=True)
for f in watch.rglob('_CodeSignature'):shutil.rmtree(f)
for f in watch.rglob('embedded.mobileprovision'):f.unlink()
ipa=r/'Readiness-WatchBridge-generic-EXPERIMENTAL-unsigned.ipa'
with zipfile.ZipFile(ipa,'w',zipfile.ZIP_DEFLATED) as z:
 for f in (build/'Payload').rglob('*'):
  if f.is_file():z.write(f,f.relative_to(build))
report={'teamSpecific':False,'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'hostBundle':hostid,'inputWatchBundle':watchid,'watchBridgeCommit':'e8403df07d0e51c0bdebe8684974f6f22f33e340','revision':44,'hostSceneLifecycle':True,'healthKitSigningVerified':False,'installationVerified':False,'windowsVerified':False,'bridgeGuardPatch':{'offset':'0xda9b4','original':'60000037','replacement':'03000014','scope':'Remove own integration bundle-ID rejection after re-signing; no entitlement changes'}}
(ipa.with_suffix('.json')).write_text(json.dumps(report,indent=2)+'\n');print(ipa)
