# Builds build\Mochi-<arch> (release): Mochi.exe plus the Swift and Visual C++ runtime DLLs it needs.
#   -Arch x64|arm64   which PCs to build for (default: this one's); either works from either
#   -Install          copy it to %LOCALAPPDATA%\Programs\Mochi and launch it
#   -Release          also zip it up as build\Mochi-windows-<arch>.zip
#   -Installer        build for both and make build\Mochi-Setup.exe (needs Inno Setup)
param([ValidateSet('x64', 'arm64')][string]$Arch, [switch]$Install, [switch]$Release, [switch]$Installer)
Set-Location $PSScriptRoot
$hostArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
if (-not $Arch) { $Arch = $hostArch }
# One version for both platforms: the Mac app's.
$version = [regex]::Match((Get-Content build.sh -Raw), 'CFBundleShortVersionString</key><string>([^<]+)').Groups[1].Value
$vs = 'C:\Program Files (x86)\Microsoft Visual Studio', 'C:\Program Files\Microsoft Visual Studio'
$swift = "$env:LOCALAPPDATA\Programs\Swift"

# Mochi.exe's icon and version details, compiled to a resource file the linker adds to it.
function Build-Resources {
    $rcExe = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\*\rc.exe' |
        Where-Object { $_.Directory.Name -eq $hostArch } | Select-Object -Last 1
    $n = ($version.Split('.') + @('0', '0', '0'))[0..3] -join ','
    New-Item -ItemType Directory .build -Force | Out-Null
    @"
1 ICON "$PSScriptRoot\windows\Mochi.ico"
1 VERSIONINFO
FILEVERSION $n
PRODUCTVERSION $n
FILEOS 0x40004
FILETYPE 1
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904b0"
    BEGIN
      VALUE "FileDescription", "Mochi"
      VALUE "ProductName", "Mochi"
      VALUE "FileVersion", "$version"
      VALUE "ProductVersion", "$version"
      VALUE "OriginalFilename", "Mochi.exe"
      VALUE "LegalCopyright", "A cat for your desktop."
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
"@ | Set-Content .build\Mochi.rc -Encoding ascii
    & $rcExe.FullName /nologo /fo .build\Mochi.res .build\Mochi.rc | Out-Host
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    "$PSScriptRoot\.build\Mochi.res"
}

# The Swift runtime DLLs. The toolchain's own are for this PC; for the other architecture, unpack
# them from the redistributable merge module the Swift installer leaves next to it.
function Get-SwiftRuntime($arch) {
    if ($arch -eq $hostArch) {
        return (Get-ChildItem "$swift\Runtimes\*\usr\bin" | Select-Object -Last 1).FullName
    }
    $dir = "$PSScriptRoot\.build\runtime-$arch"
    if (Test-Path "$dir\swiftCore.dll") { return $dir }
    $msm = Get-ChildItem "$swift\Redistributables\*\rtl.shared.$(@{ x64 = 'amd64'; arm64 = 'arm64' }[$arch]).msm" | Select-Object -Last 1
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory "$dir\cab" | Out-Null
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $call = { param($o, $name, $kind, $argList) $o.GetType().InvokeMember($name, $kind, $null, $o, $argList) }
    $query = { param($sql) $v = & $call $db OpenView InvokeMethod @($sql); & $call $v Execute InvokeMethod $null | Out-Null; $v }
    $db = & $call $installer OpenDatabase InvokeMethod @($msm.FullName, 0)
    $rec = & $call (& $query "SELECT Data FROM _Streams WHERE Name='MergeModule.CABinet'") Fetch InvokeMethod $null
    $size = & $call $rec DataSize GetProperty @(1)
    $data = & $call $rec ReadStream InvokeMethod @(1, $size, 1)   # one char per byte
    [IO.File]::WriteAllBytes("$dir\runtime.cab", [Text.Encoding]::GetEncoding(28591).GetBytes($data))
    expand.exe "$dir\runtime.cab" -F:* "$dir\cab" | Out-Null
    # Files in the cabinet are named by their key in the File table.
    $files = & $query 'SELECT File, FileName FROM File'
    while ($r = & $call $files Fetch InvokeMethod $null) {
        $key = & $call $r StringData GetProperty @(1)
        $name = ((& $call $r StringData GetProperty @(2)) -split '\|')[-1]
        if (Test-Path "$dir\cab\$key") { Move-Item "$dir\cab\$key" "$dir\$name" -Force }
    }
    $dir
}

function Build-Mochi($arch, $res) {
    $triple = @{ x64 = 'x86_64-unknown-windows-msvc'; arm64 = 'aarch64-unknown-windows-msvc' }[$arch]
    # (Compiler warnings arrive on stderr; only the exit code means failure.)
    $ErrorActionPreference = 'Continue'
    swift build -c release --build-system native --triple $triple -Xlinker $res | Out-Host
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    $ErrorActionPreference = 'Stop'
    $out = "build\Mochi-$arch"
    Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory $out | Out-Null
    Copy-Item ".build\$triple\release\Mochi.exe" $out

    # Ship the DLLs Mochi.exe loads (and the ones those load), found among the Swift runtime and the
    # Visual C++ redistributable. Everything else it uses is part of Windows.
    $dumpbin = Get-ChildItem $vs -Recurse -Filter dumpbin.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'Hostarm64\\arm64|Hostx64\\x64' } | Select-Object -First 1
    $crt = Get-ChildItem $vs -Recurse -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
        Where-Object { $_.Parent.Name -eq $arch -and $_.FullName -notmatch 'onecore|debug' } | Select-Object -Last 1
    $sources = @((Get-SwiftRuntime $arch), $crt.FullName)

    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue((Join-Path $out 'Mochi.exe'))
    $seen = @{}
    while ($queue.Count) {
        $file = $queue.Dequeue()
        $deps = & $dumpbin.FullName /nologo /dependents $file | Select-String '^\s+(\S+\.dll)\s*$' | ForEach-Object { $_.Matches[0].Groups[1].Value }
        foreach ($dll in $deps) {
            if ($seen[$dll.ToLower()]) { continue }
            $seen[$dll.ToLower()] = $true
            foreach ($dir in $sources) {
                $path = Join-Path $dir $dll
                if (Test-Path $path) {
                    Copy-Item $path $out
                    $queue.Enqueue((Join-Path $out $dll))
                    break
                }
            }
        }
    }
    Write-Host "Built $out ($((Get-ChildItem $out).Count) files)"
    $out
}

$res = Build-Resources
$archs = if ($Installer) { 'x64', 'arm64' } else { @($Arch) }
$built = @{}
foreach ($a in $archs) { $built[$a] = Build-Mochi $a $res | Select-Object -Last 1 }
$ErrorActionPreference = 'Stop'

if ($Release) {
    foreach ($a in $archs) {
        $zip = "build\Mochi-windows-$a.zip"
        Remove-Item $zip -ErrorAction SilentlyContinue
        Compress-Archive -Path "$($built[$a])\*" -DestinationPath $zip
        Write-Host "Zipped $zip"
    }
}

if ($Installer) {
    $iscc = @(Get-Command ISCC.exe -ErrorAction SilentlyContinue | ForEach-Object Source) +
        @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $iscc) { throw 'Inno Setup not found. Install it with: winget install --id JRSoftware.InnoSetup --exact' }
    & $iscc /Q "/DAppVersion=$version" windows\Mochi.iss
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    Write-Host 'Made build\Mochi-Setup.exe'
}

if ($Install) {
    $dest = "$env:LOCALAPPDATA\Programs\Mochi"
    Get-Process Mochi -ErrorAction SilentlyContinue | Stop-Process
    Start-Sleep -Milliseconds 500
    # Copied over rather than replaced, so an uninstaller left there by Mochi-Setup.exe keeps working.
    New-Item -ItemType Directory $dest -Force | Out-Null
    Copy-Item "$($built[$(if ($Installer) { $hostArch } else { $Arch })])\*" $dest -Force
    Start-Process "$dest\Mochi.exe"
    Write-Host "Installed to $dest"
}
