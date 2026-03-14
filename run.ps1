param(
    [string]$File,
    [string]$Out = "app",
    [string]$DevCmd
)

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

function Find-VsDevCmd {
    param(
        [string]$PreferredPath
    )

    $seen = @{}
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($PreferredPath) {
        $candidates.Add($PreferredPath)
    }

    $vswherePaths = @(
        (Join-Path ${Env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"),
        (Join-Path ${Env:ProgramFiles} "Microsoft Visual Studio\Installer\vswhere.exe")
    )

    foreach ($vswhere in $vswherePaths) {
        if (-not (Test-Path -LiteralPath $vswhere)) {
            continue
        }

        foreach ($pattern in @("Common7\Tools\VsDevCmd.bat", "Common7\Tools\LaunchDevCmd.bat")) {
            try {
                $found = & $vswhere -latest -products * -find $pattern 2>$null
                foreach ($path in $found) {
                    if ($path) {
                        $candidates.Add($path)
                    }
                }
            } catch {}
        }

        try {
            $installPath = & $vswhere -latest -products * -property installationPath 2>$null | Select-Object -First 1
            if ($installPath) {
                $candidates.Add((Join-Path $installPath "Common7\Tools\VsDevCmd.bat"))
                $candidates.Add((Join-Path $installPath "Common7\Tools\LaunchDevCmd.bat"))
            }
        } catch {}
    }

    $bases = @(
        ${Env:ProgramFiles(x86)},
        ${Env:ProgramFiles},
        "C:\Program Files (x86)",
        "C:\Program Files"
    )
    $versions = @("18", "2026", "2022", "2019")
    $editions = @("BuildTools", "Community", "Professional", "Enterprise")

    foreach ($base in $bases) {
        if (-not $base) {
            continue
        }

        foreach ($version in $versions) {
            foreach ($edition in $editions) {
                $toolRoot = Join-Path $base "Microsoft Visual Studio\$version\$edition\Common7\Tools"
                $candidates.Add((Join-Path $toolRoot "VsDevCmd.bat"))
                $candidates.Add((Join-Path $toolRoot "LaunchDevCmd.bat"))
            }
        }
    }

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }

        $normalized = $candidate.ToLowerInvariant()
        if ($seen.ContainsKey($normalized)) {
            continue
        }
        $seen[$normalized] = $true

        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Invoke-MsvcCompile {
    param(
        [string]$SourcePath,
        [string]$OutputPath,
        [string]$DevCmdPath
    )

    $outputName = Split-Path -Leaf $OutputPath
    $command = "cl /nologo /utf-8 /EHsc `"$SourcePath`" /Fe:`"$outputName`""

    if ($DevCmdPath) {
        cmd /c "`"$DevCmdPath`" -arch=x64 -host_arch=x64 && $command"
    } else {
        cmd /c $command
    }

    return ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $OutputPath))
}

function Test-ProgramMayNeedInput {
    param(
        [string]$SourcePath
    )

    try {
        $content = Get-Content -Raw -LiteralPath $SourcePath
        return [bool]($content -match 'scanf\s*\(' -or
            $content -match '\bcin\s*>>' -or
            $content -match 'std::cin' -or
            $content -match '\bgetline\s*\(')
    } catch {
        return $false
    }
}

Set-ConsoleUtf8
Set-Location -Path (Split-Path -Parent $PSCommandPath)

if (-not $File) {
    $latestCpp = Get-ChildItem -File *.cpp | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latestCpp) {
        Write-Host "当前目录没有可运行的 .cpp 文件。"
        exit 1
    }
    $File = $latestCpp.Name
}

if (-not (Test-Path -LiteralPath $File)) {
    Write-Host "未找到源文件: $File"
    exit 1
}

$src = (Resolve-Path -LiteralPath $File).Path

try {
    $proc = Get-Process -Name $Out -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "检测到程序正在运行，正在强制关闭..."
        Stop-Process -InputObject $proc -Force
        Start-Sleep -Milliseconds 200
    }
} catch {}

$exe = Join-Path (Get-Location) "$Out.exe"
if (Test-Path -LiteralPath $exe) {
    Remove-Item -LiteralPath $exe -Force
}

$compiled = $false

try {
    $clang = Get-Command clang++ -ErrorAction Stop
    if ($clang) {
        Write-Host "使用 clang++ 编译..."
        & $clang.Path $src "-finput-charset=UTF-8" "-fexec-charset=UTF-8" "-o" $exe
        $compiled = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exe))
    }
} catch {}

if (-not $compiled) {
    try {
        $gpp = Get-Command g++ -ErrorAction Stop
        if ($gpp) {
            Write-Host "使用 g++ 编译..."
            & $gpp.Path $src "-finput-charset=UTF-8" "-fexec-charset=UTF-8" "-o" $exe
            $compiled = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exe))
        }
    } catch {}
}

$resolvedDevCmd = Find-VsDevCmd -PreferredPath $DevCmd

if (-not $compiled -and $resolvedDevCmd) {
    Write-Host "加载 VS 开发环境并使用 cl 编译..."
    $compiled = Invoke-MsvcCompile -SourcePath $src -OutputPath $exe -DevCmdPath $resolvedDevCmd
}

if (-not $compiled) {
    try {
        $msvc = Get-Command cl -ErrorAction Stop
        if ($msvc -and (Test-MsvcEnvironmentReady)) {
            Write-Host "使用 MSVC cl 编译..."
            $compiled = Invoke-MsvcCompile -SourcePath $src -OutputPath $exe
        }
    } catch {}
}

if (-not $compiled) {
    @'
未检测到可用的 C/C++ 编译器。
请安装以下任一工具并重试：
 - LLVM (clang++)
 - MSYS2 MinGW (g++)
 - Microsoft Visual C++ Build Tools (cl)
'@ | Write-Host
    exit 2
}

Write-Host "运行：$exe"
if (Test-ProgramMayNeedInput -SourcePath $src) {
    Write-Host "检测到当前程序可能需要终端输入；如果看到光标停住，请直接输入内容后回车。"
}
& $exe
