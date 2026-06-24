# Rokid iOS Plugin GitHub Actions Build

Use this when the local machine does not have macOS/Xcode.

## What It Builds

The workflow `.github/workflows/build-rokid-ios-plugin.yml` runs on a GitHub macOS runner and builds:

- `RokidCXRLUniPlugin.framework`
- `Rokid-Glass-ios-nativeplugin.zip`

The plugin zip contains:

- `nativeplugins/Rokid-Glass/package.json`
- `nativeplugins/Rokid-Glass/ios/*.framework`

## How To Run

1. Push this project to GitHub.
2. Open the GitHub repository.
3. Go to `Actions`.
4. Select `Build Rokid iOS Plugin`.
5. Click `Run workflow`.
6. Download the artifact named `Rokid-Glass-ios-nativeplugin`.

## How To Use The Artifact

Extract `Rokid-Glass-ios-nativeplugin.zip`.

Copy the extracted `Rokid-Glass/ios/RokidCXRLUniPlugin.framework` back to:

```text
nativeplugins/Rokid-Glass/ios/RokidCXRLUniPlugin.framework
```

Then rebuild the iOS custom base in HBuilderX and install it fresh on the iPhone.

## Notes

The build script compiles the plugin as a static framework, matching the current checked-in `RokidCXRLUniPlugin.framework` format. Set `IOS_DEPLOYMENT_TARGET=13.0` for a lower-iOS build, and make sure the Rokid SDK frameworks are also available for that target.

If GitHub Actions fails while importing `RGCxrClient.framework`, the most likely reason is an Xcode/Swift version mismatch with Rokid's prebuilt Swift framework. In that case, use a runner with a newer Xcode image or build on a cloud Mac with the same/newer Xcode.
