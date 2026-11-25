# Builds dist\RaidPortraits-<version>.zip with one top-level RaidPortraits folder.
#   powershell -ExecutionPolicy Bypass -File tools\package.ps1
# Entry names use forward slashes, which CurseForge and the game's extractors expect.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$addon = Join-Path $root "RaidPortraits"
$toc = Get-Content (Join-Path $addon "RaidPortraits.toc") -Raw
$version = [regex]::Match($toc, "(?m)^## Version:\s*(\S+)").Groups[1].Value
if (-not $version) { throw "No version in the TOC" }
if (-not (Select-String -Path (Join-Path $addon "CHANGELOG.md") -Pattern "^## $([regex]::Escape($version))\s*$" -Quiet)) {
    throw "CHANGELOG.md has no entry for $version"
}

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$dest = Join-Path $dist "RaidPortraits-$version.zip"
if (Test-Path $dest) { Remove-Item $dest }

$zip = [System.IO.Compression.ZipFile]::Open($dest, "Create")
try {
    Get-ChildItem $addon -Recurse -File | Sort-Object FullName | ForEach-Object {
        $rel = "RaidPortraits/" + $_.FullName.Substring($addon.Length + 1).Replace("\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel, "Optimal") | Out-Null
    }
} finally { $zip.Dispose() }

# Verify
$check = [System.IO.Compression.ZipFile]::OpenRead($dest)
try {
    $names = $check.Entries | ForEach-Object { $_.FullName }
    foreach ($need in "RaidPortraits/RaidPortraits.toc", "RaidPortraits/Media/Logo.tga", "RaidPortraits/Media/Circle.tga",
                      "RaidPortraits/CHANGELOG.md", "RaidPortraits/INSTALL.txt") {
        if ($names -notcontains $need) { throw "Missing $need" }
    }
    foreach ($line in ($toc -split "`r?`n")) {
        $f = $line.Trim()
        if ($f -and -not $f.StartsWith("#") -and $names -notcontains "RaidPortraits/$f") { throw "TOC lists $f but it isn't packaged" }
    }
    if ($names | Where-Object { -not $_.StartsWith("RaidPortraits/") -or $_.Contains("\") }) { throw "Bad entry path" }
    "Verified $($names.Count) packaged files:"
    $names | ForEach-Object { "  $_" }
} finally { $check.Dispose() }
"{0} ({1:N0} bytes)" -f $dest, (Get-Item $dest).Length
