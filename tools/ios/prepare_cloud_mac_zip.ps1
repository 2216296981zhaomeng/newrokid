param(
    [string]$SampleDir = "F:\glass\ios_cxr_l_sample",
    [string]$OutputZip = "F:\glass\rokid-ios-cloud-mac-input.zip"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$samplePath = (Resolve-Path -LiteralPath $SampleDir).Path
$outputParent = Split-Path -Parent $OutputZip
if (-not (Test-Path -LiteralPath $outputParent)) {
    New-Item -ItemType Directory -Path $outputParent | Out-Null
}

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rokid-ios-cloud-mac-input-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stageRoot | Out-Null

try {
    Copy-Item -LiteralPath $samplePath -Destination (Join-Path $stageRoot "ios_cxr_l_sample") -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $scriptDir "build_rokid_ios_frameworks_on_mac.sh") -Destination (Join-Path $stageRoot "build_rokid_ios_frameworks_on_mac.sh") -Force

    @"
# Rokid iOS Cloud Mac Build

Run on macOS:

```bash
unzip rokid-ios-cloud-mac-input.zip
cd rokid-ios-cloud-mac-input-*
chmod +x build_rokid_ios_frameworks_on_mac.sh
./build_rokid_ios_frameworks_on_mac.sh
```

Download `dist/rokid-ios-frameworks.zip` back to Windows after the script finishes.
"@ | Set-Content -LiteralPath (Join-Path $stageRoot "README.md") -Encoding UTF8

    if (Test-Path -LiteralPath $OutputZip) {
        Remove-Item -LiteralPath $OutputZip -Force
    }
    Compress-Archive -Path (Join-Path $stageRoot "*") -DestinationPath $OutputZip -Force
    Write-Output "Created $OutputZip"
} finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}
