$ErrorActionPreference = "Stop"

function Set-ConsoleUtf8 {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    $script:OutputEncoding = $utf8
    try {
        & "$env:SystemRoot\System32\chcp.com" 65001 > $null
    } catch {}
}

function Test-MsvcEnvironmentReady {
    return [bool]($env:INCLUDE -and $env:LIB)
}

Set-ConsoleUtf8
Set-Location -Path (Split-Path -Parent $PSCommandPath)

$sourceFiles = Get-ChildItem -File *.cpp
if (-not $sourceFiles) {
    Write-Host "当前目录未找到任何 .cpp 源文件。"
    exit 1
}

if (-not (Test-Path -LiteralPath "bin")) {
    New-Item -ItemType Directory -Path "bin" | Out-Null
}

$outputPath = Join-Path (Get-Location) "bin\app.exe"
$sourcePaths = $sourceFiles | ForEach-Object { $_.FullName }

try {
    $gpp = Get-Command g++ -ErrorAction Stop
    if ($gpp) {
        Write-Host "使用 g++ 编译全部源文件..."
        & $gpp.Path "-std=c++17" "-O2" "-finput-charset=UTF-8" "-fexec-charset=UTF-8" "-o" $outputPath $sourcePaths
        exit $LASTEXITCODE
    }
} catch {}

try {
    $clang = Get-Command clang++ -ErrorAction Stop
    if ($clang) {
        Write-Host "使用 clang++ 编译全部源文件..."
        & $clang.Path "-std=c++17" "-O2" "-finput-charset=UTF-8" "-fexec-charset=UTF-8" "-o" $outputPath $sourcePaths
        exit $LASTEXITCODE
    }
} catch {}

try {
    $cl = Get-Command cl -ErrorAction Stop
    if ($cl -and (Test-MsvcEnvironmentReady)) {
        Write-Host "使用 MSVC cl 编译全部源文件..."
        $sourceNames = $sourceFiles | ForEach-Object { $_.Name }
        cmd /c "cl /nologo /utf-8 /EHsc /std:c++17 /O2 $($sourceNames -join ' ') /Fe:`"$outputPath`""
        exit $LASTEXITCODE
    }
} catch {}

Write-Host "未检测到可用且已完成环境初始化的编译器。请优先使用 run.ps1 或 run_with_devcmd.ps1。"
exit 1
