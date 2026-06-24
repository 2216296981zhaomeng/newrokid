#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-13.0}"

if [[ -d "$ROOT/ios_cxr_l_sample/ios_cxr_l_sample" ]]; then
  SAMPLE_DIR="$ROOT/ios_cxr_l_sample/ios_cxr_l_sample"
elif [[ -d "$ROOT/../ios_cxr_l_sample/ios_cxr_l_sample" ]]; then
  SAMPLE_DIR="$ROOT/../ios_cxr_l_sample/ios_cxr_l_sample"
elif [[ -d "$ROOT/../../ios_cxr_l_sample/ios_cxr_l_sample" ]]; then
  SAMPLE_DIR="$ROOT/../../ios_cxr_l_sample/ios_cxr_l_sample"
else
  echo "Cannot find ios_cxr_l_sample/ios_cxr_l_sample next to this script."
  exit 1
fi

DERIVED_DATA="$ROOT/build/DerivedData"
DIST_DIR="$ROOT/dist"
OUT_DIR="$DIST_DIR/ios-frameworks"
OUT_ZIP="$DIST_DIR/rokid-ios-frameworks.zip"

rm -rf "$DERIVED_DATA" "$OUT_DIR" "$OUT_ZIP"
mkdir -p "$OUT_DIR" "$DIST_DIR"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is missing. Install Xcode and select it with xcode-select."
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods is missing. Install with: sudo gem install cocoapods"
  exit 1
fi

echo "Using sample: $SAMPLE_DIR"
echo "Using iOS deployment target: $IOS_DEPLOYMENT_TARGET"
cd "$SAMPLE_DIR"

pod install --repo-update

xcodebuild \
  -workspace "$SAMPLE_DIR/CXRClientDemo.xcworkspace" \
  -scheme CXRClientDemo \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
  SKIP_INSTALL=NO \
  clean build

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Release-iphoneos"

copy_framework() {
  local name="$1"
  local found=""
  found="$(find "$PRODUCTS_DIR" "$SAMPLE_DIR/Pods" -type d -name "$name.framework" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$found" ]]; then
    echo "Missing $name.framework"
    exit 1
  fi
  echo "Copying $name.framework from $found"
  rm -rf "$OUT_DIR/$name.framework"
  rsync -a --delete "$found/" "$OUT_DIR/$name.framework/"
  if [[ ! -f "$OUT_DIR/$name.framework/$name" ]]; then
    echo "$name.framework binary is missing after copy"
    exit 1
  fi
}

minimum_os_version() {
  local framework="$1"
  local plist="$OUT_DIR/$framework.framework/Info.plist"
  /usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$plist" 2>/dev/null || true
}

version_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, av, "."); split(b, bv, ".");
    for (i = 1; i <= 3; i++) {
      ai = av[i] + 0; bi = bv[i] + 0;
      if (ai > bi) exit 0;
      if (ai < bi) exit 1;
    }
    exit 1;
  }'
}

copy_framework "RGCxrClient"
copy_framework "RGCoreKit"
copy_framework "CocoaLumberjack"

for framework in RGCxrClient RGCoreKit CocoaLumberjack; do
  min_os="$(minimum_os_version "$framework")"
  if [[ -n "$min_os" ]] && version_gt "$min_os" "$IOS_DEPLOYMENT_TARGET"; then
    echo "$framework.framework MinimumOSVersion is $min_os, higher than requested $IOS_DEPLOYMENT_TARGET."
    echo "The resolved Rokid SDK cannot be used for a lower-iOS build. Use an SDK release/source that supports iOS $IOS_DEPLOYMENT_TARGET."
    exit 1
  fi
done

if command -v otool >/dev/null 2>&1; then
  otool -L "$OUT_DIR/RGCxrClient.framework/RGCxrClient" > "$DIST_DIR/otool-RGCxrClient.txt" || true
  otool -L "$OUT_DIR/RGCoreKit.framework/RGCoreKit" > "$DIST_DIR/otool-RGCoreKit.txt" || true
  otool -L "$OUT_DIR/CocoaLumberjack.framework/CocoaLumberjack" > "$DIST_DIR/otool-CocoaLumberjack.txt" || true
fi

cd "$OUT_DIR"
/usr/bin/zip -qry "$OUT_ZIP" .

echo "Built frameworks:"
find "$OUT_DIR" -maxdepth 2 -type f -perm -111 -print
echo "Output zip: $OUT_ZIP"
