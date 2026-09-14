$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Show-Disks([string]$Label) {
    Write-Host "==== $Label ====" -ForegroundColor Cyan
    Get-PSDrive -PSProvider FileSystem | Format-Table Name,Used,Free,Root -AutoSize
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The official Windows route requires Administrator privileges.'
}

Show-Disks 'Disk space before cleanup'

# Free space from hosted-runner SDKs that are not needed by DISM/diskpart/QEMU.
$targets = @(
    $env:ANDROID_HOME,
    $env:ANDROID_SDK_ROOT,
    $env:AGENT_TOOLSDIRECTORY,
    'C:\Android',
    'C:\Program Files (x86)\Android',
    'C:\Program Files\Android',
    'C:\Program Files\Microsoft Visual Studio',
    'C:\Program Files (x86)\Microsoft Visual Studio',
    'C:\Program Files\dotnet'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

foreach ($p in $targets) {
    Write-Host "Removing unused runner payload: $p"
    try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
    catch { Write-Warning "Could not completely remove $p : $($_.Exception.Message)" }
}

Show-Disks 'Disk space after cleanup'

# Work on whichever fixed filesystem has the most free space.
$bestDrive = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 } | Sort-Object Free -Descending | Select-Object -First 1
if (-not $bestDrive) { throw 'No writable filesystem found.' }
$work = Join-Path $bestDrive.Root ("droidvm-build-" + $env:GITHUB_RUN_ID)
New-Item -ItemType Directory -Force $work | Out-Null
Write-Host "Working directory: $work"

$builder = Join-Path $work 'builder'
git clone --depth 1 https://github.com/Droid-VM/win11-arm64-image-builder.git $builder
if ($LASTEXITCODE -ne 0) { throw 'Failed to clone the official DroidVM image builder.' }

# Obtain a current official Microsoft Windows 11 ARM64 retail ISO URL with Fido.
$fido = Join-Path $work 'Fido.ps1'
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1' -OutFile $fido
$fidoOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $fido -Win 11 -Rel Latest -Ed 'Pro/Home' -Lang English -Arch ARM64 -GetUrl 2>&1
$fidoOut | ForEach-Object { Write-Host $_ }
$isoUrl = $fidoOut | ForEach-Object { "$_" } | Where-Object { $_ -match '^https?://' } | Select-Object -Last 1

# Official Microsoft CDN fallback (Windows 11 25H2 ARM64 English consumer ISO).
if (-not $isoUrl) {
    Write-Warning 'Fido did not return a URL; using the Microsoft 25H2 ARM64 fallback URL.'
    $isoUrl = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34f-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENT_CONSUMER_A64FRE_en-us.iso'
}

$iso = Join-Path $work 'windows11-arm64.iso'
Write-Host 'Downloading official Windows 11 ARM64 ISO from Microsoft...'
& curl.exe -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o $iso $isoUrl
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $iso)) { throw 'Windows ISO download failed.' }
Write-Host ("ISO size: {0:N2} GiB" -f ((Get-Item $iso).Length / 1GB))

$qcow = Join-Path $work 'win11-droidvm-final.qcow2'
$pkg  = Join-Path $work 'win11-droidvm-final.vmpkg'

# Configure the official offline builder. Windows 11 Pro is index 6 in the
# Microsoft consumer multi-edition ISO; the builder validates the index first.
$env:SRC_ISO = $iso
$env:IMAGE_INDEX = '6'
$env:OUT_QCOW = $qcow
$env:OUT_VMPKG = ''
$env:DRIVERS_DIR = 'https://github.com/Droid-VM/gunyah-guest-drivers-windows/releases/download/dev/gunyah-arm64-drivers.zip'
$env:OPENSSH_SRC = 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-ARM64-v10.0.0.0.msi'
$env:DVM_USERNAME = 'USER'
$env:DVM_PASSWORD = 'DroidVM'
$env:SSH_PUBKEY = ''
$env:DISK_SIZE_MB = '40960'
$env:EMS_SAC_SOURCE = 'skip'
$env:COMPRESS = '1'
$env:DRIVER_DIR = 'ZIP/drivers'
$env:DRIVER_INSTALL = 'NetKVM rdmapool pvmpower vioinput viostor vioscsi viosnd viofs'
$env:DRIVER_CERT = 'ZIP/DroidVM_Test.cer'
$env:QEMU_IMG_INSTALL = '1'

Write-Host 'Starting official DroidVM Windows builder...' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $builder 'windows\build.ps1')
if ($LASTEXITCODE -ne 0) { throw "DroidVM builder failed with exit code $LASTEXITCODE" }
if (-not (Test-Path $qcow)) { throw 'Builder completed without creating the qcow2.' }

# No longer required; remove before packaging to keep peak runner storage lower.
Remove-Item -LiteralPath $iso -Force -ErrorAction SilentlyContinue

Write-Host 'Packing a ready-to-import .vmpkg...' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $builder 'pack-vmpkg.ps1') -Qcow2 $qcow -Config (Join-Path $builder 'vms.json') -Out $pkg -Compression none -Threads 0
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pkg)) { throw 'vmpkg packaging failed.' }

Write-Host ("qcow2: {0:N2} GiB" -f ((Get-Item $qcow).Length / 1GB))
Write-Host ("vmpkg: {0:N2} GiB" -f ((Get-Item $pkg).Length / 1GB))
Remove-Item -LiteralPath $qcow -Force

$releaseDir = Join-Path $work 'release'
New-Item -ItemType Directory -Force $releaseDir | Out-Null

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pkg).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $releaseDir 'SHA256.txt') -Value "$hash  win11-droidvm-final.vmpkg" -Encoding ASCII

$readme = @'
DroidVM Windows 11 ARM64 package
=================================
Edition: Windows 11 Pro ARM64
Local account: USER
Password: DroidVM

Download every win11-droidvm-final.vmpkg.partNNN file into the same folder.

Android / Termux:
  cat win11-droidvm-final.vmpkg.part* > win11-droidvm-final.vmpkg

Windows PowerShell:
  $out = [IO.File]::Create('win11-droidvm-final.vmpkg')
  Get-ChildItem 'win11-droidvm-final.vmpkg.part*' | Sort-Object Name | ForEach-Object {
    $in = [IO.File]::OpenRead($_.FullName)
    $in.CopyTo($out)
    $in.Dispose()
  }
  $out.Dispose()

Then import win11-droidvm-final.vmpkg in DroidVM.
SHA256.txt contains the hash of the complete reassembled vmpkg.
'@
Set-Content -LiteralPath (Join-Path $releaseDir 'README_REASSEMBLE.txt') -Value $readme -Encoding UTF8

# Split below GitHub's per-release-asset size limit.
$partSize = 1500MB
$src = [IO.File]::OpenRead($pkg)
try {
    $buffer = New-Object byte[] (8MB)
    $part = 1
    while ($src.Position -lt $src.Length) {
        $partPath = Join-Path $releaseDir ("win11-droidvm-final.vmpkg.part{0:D3}" -f $part)
        $dst = [IO.File]::Create($partPath)
        try {
            [long]$remaining = [Math]::Min([long]$partSize, $src.Length - $src.Position)
            while ($remaining -gt 0) {
                $want = [int][Math]::Min([long]$buffer.Length, $remaining)
                $read = $src.Read($buffer, 0, $want)
                if ($read -le 0) { break }
                $dst.Write($buffer, 0, $read)
                $remaining -= $read
            }
        } finally {
            $dst.Dispose()
        }
        Write-Host "Created $(Split-Path $partPath -Leaf)"
        $part++
    }
} finally {
    $src.Dispose()
}
Remove-Item -LiteralPath $pkg -Force

Write-Host 'Release files:' -ForegroundColor Cyan
Get-ChildItem $releaseDir | Format-Table Name,Length -AutoSize

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is not available on runner.' }
if (-not $env:GH_TOKEN) { throw 'GH_TOKEN is missing.' }

$tag = "droidvm-win11-$env:GITHUB_RUN_NUMBER"
$notes = @"
Ready-to-import DroidVM Windows 11 Pro ARM64 package built with the official Droid-VM/win11-arm64-image-builder and the current DroidVM Gunyah/VirtIO dev drivers.

SHA-256 of the reassembled vmpkg:
$hash

Download all .partNNN assets plus README_REASSEMBLE.txt, join the numbered parts, then import win11-droidvm-final.vmpkg in DroidVM.
"@

& gh release create $tag --repo $env:GITHUB_REPOSITORY --target $env:GITHUB_SHA --title 'DroidVM Windows 11 Pro ARM64' --notes $notes
if ($LASTEXITCODE -ne 0) { throw 'Failed to create GitHub release.' }

Get-ChildItem -LiteralPath $releaseDir -File | Sort-Object Name | ForEach-Object {
    Write-Host "Uploading release asset $($_.Name)..."
    & gh release upload $tag $_.FullName --repo $env:GITHUB_REPOSITORY --clobber
    if ($LASTEXITCODE -ne 0) { throw "Failed to upload $($_.Name)" }
}

Write-Host "Release: https://github.com/$env:GITHUB_REPOSITORY/releases/tag/$tag" -ForegroundColor Green
Show-Disks 'Final disk space'
