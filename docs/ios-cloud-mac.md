# Rokid iOS Cloud Mac Build

This is a fallback flow. The active project currently uses prebuilt frameworks copied from `F:\glass\Rokid-CXRL`, so cloud Mac generation is not required unless those prebuilt frameworks stop working or a newer Rokid SDK needs to be rebuilt.

## 1. Prepare Upload Zip On Windows

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\nativeplugins\Rokid-Glass\tools\ios\prepare_cloud_mac_zip.ps1
```

This creates:

```text
F:\glass\rokid-ios-cloud-mac-input.zip
```

Upload that zip to the cloud Mac.

## 2. Build On Cloud Mac

On the cloud Mac:

```bash
unzip rokid-ios-cloud-mac-input.zip -d rokid-ios-cloud-mac-input
cd rokid-ios-cloud-mac-input
chmod +x build_rokid_ios_frameworks_on_mac.sh
IOS_DEPLOYMENT_TARGET=13.0 ./build_rokid_ios_frameworks_on_mac.sh
```

The script runs `pod install` and `xcodebuild` against the Rokid sample, then exports:

```text
dist/rokid-ios-frameworks.zip
```

Download this zip back to Windows.

## 3. Import Frameworks Back Into The Uni-App Plugin

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\nativeplugins\Rokid-Glass\tools\ios\import_ios_frameworks.ps1 -ZipPath F:\glass\rokid-ios-frameworks.zip
```

This copies the frameworks into `nativeplugins/Rokid-Glass/ios`, restores the real Swift bridge, and re-enables the iOS native plugin in `manifest.json` and `package.json`.

For a lower-iOS package, import with the same deployment target:

```powershell
powershell -ExecutionPolicy Bypass -File .\nativeplugins\Rokid-Glass\tools\ios\import_ios_frameworks.ps1 -ZipPath F:\glass\rokid-ios-frameworks.zip -IosDeploymentTarget 13.0
```

The import step checks Swift interfaces and stops if a copied framework was still built for a higher iOS version.

Expected embedded dynamic frameworks:

- `RGCxrClient.framework`
- `RGCoreKit.framework`
- `CocoaLumberjack.framework`

After import, rebuild the iOS custom base in HBuilderX and install it fresh on the iPhone.
