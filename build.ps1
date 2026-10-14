# Builds build\Mochi (release): Mochi.exe plus the Swift and Visual C++ runtime DLLs it needs.
#   -Arch x64|arm64   which PCs to build for (default: this one's); either works from either
#   -Install          copy it to %LOCALAPPDATA%\Programs\Mochi and launch it
#   -Release          also zip it up as build\Mochi-windows-<arch>.zip
param([ValidateSet('x64', 'arm64')][string]$Arch, [switch]$Install, [switch]$Release)
Set-Location $PSScriptRoot
$hostArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
if (-not $Arch) { $Arch = $hostArch }
$triple = @{ x64 = 'x86_64-unknown-windows-msvc'; arm64 = 'aarch64-unknown-windows-msvc' }[$Arch]

# (Compiler warnings arrive on stderr; only the exit code means failure.)
swift build -c release --build-system native --triple $triple
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$ErrorActionPreference = 'Stop'
$out = 'build\Mochi'
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $out | Out-Null
Copy-Item ".build\$triple\release\Mochi.exe" $out

# The Swift runtime DLLs. The toolchain's own are for this PC; for the other architecture, unpack
# them from the redistributable merge module the Swift installer leaves next to it.
$swift = "$env:LOCALAPPDATA\Programs\Swift"
if ($Arch -eq $hostArch) {
    $swiftRuntime = (Get-ChildItem "$swift\Runtimes\*\usr\bin" | Select-Object -Last 1).FullName
} else {
    $msm = Get-ChildItem "$swift\Redistributables\*\rtl.shared.$(@{ x64 = 'amd64'; arm64 = 'arm64' }[$Arch]).msm" | Select-Object -Last 1
    $swiftRuntime = "$PSScriptRoot\.build\runtime-$Arch"
    if (-not (Test-Path "$swiftRuntime\swiftCore.dll")) {
        Remove-Item $swiftRuntime -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory "$swiftRuntime\cab" | Out-Null
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $call = { param($o, $name, $kind, $argList) $o.GetType().InvokeMember($name, $kind, $null, $o, $argList) }
        $query = { param($sql) $v = & $call $db OpenView InvokeMethod @($sql); & $call $v Execute InvokeMethod $null | Out-Null; $v }
        $db = & $call $installer OpenDatabase InvokeMethod @($msm.FullName, 0)
        $rec = & $call (& $query "SELECT Data FROM _Streams WHERE Name='MergeModule.CABinet'") Fetch InvokeMethod $null
        $size = & $call $rec DataSize GetProperty @(1)
        $data = & $call $rec ReadStream InvokeMethod @(1, $size, 1)   # one char per byte
        [IO.File]::WriteAllBytes("$swiftRuntime\runtime.cab", [Text.Encoding]::GetEncoding(28591).GetBytes($data))
        expand.exe "$swiftRuntime\runtime.cab" -F:* "$swiftRuntime\cab" | Out-Null
        # Files in the cabinet are named by their key in the File table.
        $files = & $query 'SELECT File, FileName FROM File'
        while ($r = & $call $files Fetch InvokeMethod $null) {
            $key = & $call $r StringData GetProperty @(1)
            $name = ((& $call $r StringData GetProperty @(2)) -split '\|')[-1]
            if (Test-Path "$swiftRuntime\cab\$key") { Move-Item "$swiftRuntime\cab\$key" "$swiftRuntime\$name" -Force }
        }
    }
}

# Ship the DLLs Mochi.exe loads (and the ones those load), found among the Swift runtime and the
# Visual C++ redistributable. Everything else it uses is part of Windows.
$vs = 'C:\Program Files (x86)\Microsoft Visual Studio', 'C:\Program Files\Microsoft Visual Studio'
$dumpbin = Get-ChildItem $vs -Recurse -Filter dumpbin.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'Hostarm64\\arm64|Hostx64\\x64' } | Select-Object -First 1
$crt = Get-ChildItem $vs -Recurse -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
    Where-Object { $_.Parent.Name -eq $Arch -and $_.FullName -notmatch 'onecore|debug' } | Select-Object -Last 1
$sources = @($swiftRuntime, $crt.FullName)

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
Write-Host "Built $out for $Arch ($((Get-ChildItem $out).Count) files)"

if ($Release) {
    $zip = "build\Mochi-windows-$Arch.zip"
    Remove-Item $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path $out -DestinationPath $zip
    Write-Host "Zipped $zip"
}

if ($Install) {
    $dest = "$env:LOCALAPPDATA\Programs\Mochi"
    Get-Process Mochi -ErrorAction SilentlyContinue | Stop-Process
    Start-Sleep -Milliseconds 500
    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item $out $dest -Recurse
    Start-Process "$dest\Mochi.exe"
    Write-Host "Installed to $dest"
}
