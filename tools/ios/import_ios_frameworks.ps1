param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [string]$PluginDir = "",
    [string]$RealIosDir = "F:\glass\Rokid-Glass-ios.disabled-20260529",
    [string]$IosDeploymentTarget = "13.0"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($PluginDir)) {
    $PluginDir = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\..")).Path
} else {
    $PluginDir = (Resolve-Path -LiteralPath $PluginDir).Path
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PluginDir "..\..")).Path
$iosDir = Join-Path $PluginDir "ios"
$classesDir = Join-Path $iosDir "Classes"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rokid-ios-frameworks-" + [guid]::NewGuid().ToString("N"))

function Assert-Inside {
    param([string]$Path, [string]$Root)
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify outside expected root: $resolvedPath"
    }
}

function Copy-Framework {
    param([string]$Name)
    $source = Get-ChildItem -LiteralPath $tmp -Recurse -Directory -Filter "$Name.framework" | Select-Object -First 1
    if (-not $source) {
        throw "Missing $Name.framework in $ZipPath"
    }
    $target = Join-Path $iosDir "$Name.framework"
    if (Test-Path -LiteralPath $target) {
        Assert-Inside -Path $target -Root $PluginDir
        Remove-Item -LiteralPath $target -Recurse -Force
    }
    Copy-Item -LiteralPath $source.FullName -Destination $target -Recurse -Force
    $binary = Join-Path $target $Name
    if (-not (Test-Path -LiteralPath $binary)) {
        throw "$Name.framework copied but binary is missing"
    }
    Assert-SwiftInterfaceTarget -FrameworkPath $target -Name $Name
}

function Assert-SwiftInterfaceTarget {
    param([string]$FrameworkPath, [string]$Name)
    $swiftInterface = Get-ChildItem -LiteralPath $FrameworkPath -Recurse -File -Filter "arm64-apple-ios.swiftinterface" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $swiftInterface) {
        return
    }
    $header = (Get-Content -LiteralPath $swiftInterface.FullName -TotalCount 8) -join "`n"
    $match = [regex]::Match($header, "arm64-apple-ios([0-9.]+)")
    if (-not $match.Success) {
        return
    }
    $frameworkTarget = [version]$match.Groups[1].Value
    $requestedTarget = [version]$IosDeploymentTarget
    if ($frameworkTarget -gt $requestedTarget) {
        throw "$Name.framework was built for iOS $frameworkTarget, higher than requested iOS $requestedTarget. Rebuild or replace the Rokid SDK framework before importing."
    }
}

try {
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tmp -Force

    New-Item -ItemType Directory -Path $iosDir -Force | Out-Null
    New-Item -ItemType Directory -Path $classesDir -Force | Out-Null

    Copy-Framework -Name "RGCxrClient"
    Copy-Framework -Name "RGCoreKit"
    Copy-Framework -Name "CocoaLumberjack"

    $realClasses = Join-Path $RealIosDir "Classes"
    if (-not (Test-Path -LiteralPath $realClasses)) {
        throw "Missing real iOS bridge classes: $realClasses"
    }

    foreach ($file in @("RokidGlassModule.h", "RokidGlassModule.m", "RokidGlassBridge.swift", "RokidGlassPluginProxy.swift")) {
        $src = Join-Path $realClasses $file
        if (-not (Test-Path -LiteralPath $src)) {
            throw "Missing bridge source: $src"
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $classesDir $file) -Force
    }

    $packagePath = Join-Path $PluginDir "package.json"
    $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
    $iosConfig = [ordered]@{
        plugins = @(
            [ordered]@{
                type = "module"
                name = "Rokid-Glass"
                class = "RokidGlassModule"
            }
        )
        hooksClass = "RokidGlassPluginProxy"
        integrateType = "library"
        frameworks = @(
            "RGCxrClient.framework",
            "RGCoreKit.framework",
            "CocoaLumberjack.framework",
            "CoreBluetooth.framework",
            "AVFoundation.framework",
            "Combine.framework",
            "UIKit.framework",
            "Foundation.framework"
        )
        embedFrameworks = @(
            "RGCxrClient.framework",
            "RGCoreKit.framework",
            "CocoaLumberjack.framework"
        )
        capabilities = [ordered]@{
            plists = [ordered]@{
                UIBackgroundModes = @("bluetooth-central")
            }
        }
        privacies = @(
            "NSBluetoothAlwaysUsageDescription",
            "NSBluetoothPeripheralUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSCameraUsageDescription"
        )
        deploymentTarget = $IosDeploymentTarget
        validArchitectures = @("arm64")
        embedSwift = $true
    }
    if (-not $package._dp_nativeplugin) {
        $package | Add-Member -MemberType NoteProperty -Name "_dp_nativeplugin" -Value ([ordered]@{})
    }
    $package._dp_nativeplugin | Add-Member -MemberType NoteProperty -Name "ios" -Value $iosConfig -Force
    $package | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $packagePath -Encoding UTF8

    $manifestPath = Join-Path $repoRoot "manifest.json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw
    $pattern = '("Rokid-Glass"\s*:\s*\{\s*"__plugin_info__"\s*:\s*\{[^{}]*?"platforms"\s*:\s*)"Android"'
    $updated = [regex]::Replace($manifest, $pattern, '$1"Android,iOS"', 1, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($updated -eq $manifest) {
        throw "Failed to switch Rokid-Glass platforms to Android,iOS in manifest.json"
    }
    Set-Content -LiteralPath $manifestPath -Value $updated -Encoding UTF8

    Write-Output "Imported Rokid iOS frameworks and enabled iOS plugin."
} finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}
