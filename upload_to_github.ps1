param(
    [string]$RepoUrl,
    [string]$Message
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

function Find-Git {
    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $gitFromPath = (Get-Command git -ErrorAction Stop).Path
        if ($gitFromPath) {
            $candidates.Add($gitFromPath)
        }
    } catch {}

    foreach ($path in @(
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files\Git\bin\git.exe",
        "C:\Program Files (x86)\Git\cmd\git.exe",
        "C:\Program Files (x86)\Git\bin\git.exe"
    )) {
        $candidates.Add($path)
    }

    $desktopRoot = Join-Path $env:LOCALAPPDATA "GitHubDesktop"
    if (Test-Path -LiteralPath $desktopRoot) {
        $desktopApps = Get-ChildItem -LiteralPath $desktopRoot -Directory -Filter "app-*"
        foreach ($app in ($desktopApps | Sort-Object Name -Descending)) {
            $candidates.Add((Join-Path $app.FullName "resources\app\git\cmd\git.exe"))
            $candidates.Add((Join-Path $app.FullName "resources\app\git\bin\git.exe"))
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $script:GitExe @Arguments 2>&1
    $ErrorActionPreference = $previousPreference
    $exitCode = $LASTEXITCODE
    if ($output) {
        $output | ForEach-Object { Write-Host $_ }
    }
    if ($exitCode -ne 0) {
        throw "Git 命令执行失败：git $($Arguments -join ' ')"
    }
}

function Invoke-GitWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Invoke-Git -Arguments $Arguments
            return
        } catch {
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            Write-Host "Git 命令第 $attempt 次失败，$DelaySeconds 秒后重试..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $script:GitExe @Arguments 2>$null
    $ErrorActionPreference = $previousPreference
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        return $null
    }
    return ($output | Out-String).Trim()
}

function Ensure-GitIgnore {
    $gitIgnorePath = Join-Path $script:RepoRoot ".gitignore"
    if (Test-Path -LiteralPath $gitIgnorePath) {
        return
    }

    @'
*.exe
*.obj
*.ilk
*.pdb
*.idb
*.log
bin/
.vs/
'@ | Set-Content -LiteralPath $gitIgnorePath -Encoding utf8
}

function Ensure-Repository {
    $gitDir = Join-Path $script:RepoRoot ".git"
    if (Test-Path -LiteralPath $gitDir) {
        return
    }

    Write-Host "当前目录还不是 Git 仓库，正在初始化..."
    Invoke-Git -Arguments @("-C", $script:RepoRoot, "init", "-b", "main")
}

function Ensure-UserIdentity {
    $name = Get-GitOutput -Arguments @("-C", $script:RepoRoot, "config", "user.name")
    $email = Get-GitOutput -Arguments @("-C", $script:RepoRoot, "config", "user.email")

    if ($name -and $email) {
        return
    }

    Write-Host "这台机器还没给当前仓库配置 Git 身份。"
    $inputName = Read-Host "请输入提交显示名，例如你的昵称"
    $inputEmail = Read-Host "请输入 GitHub 绑定邮箱"

    if (-not $inputName -or -not $inputEmail) {
        throw "没有拿到完整的 Git 身份信息，已停止。"
    }

    Invoke-Git -Arguments @("-C", $script:RepoRoot, "config", "user.name", $inputName)
    Invoke-Git -Arguments @("-C", $script:RepoRoot, "config", "user.email", $inputEmail)
}

function Ensure-OriginRemote {
    $origin = Get-GitOutput -Arguments @("-C", $script:RepoRoot, "remote", "get-url", "origin")
    if ($origin) {
        Write-Host "当前远程仓库：$origin"
        return
    }

    if (-not $RepoUrl) {
        Write-Host "你还没有给这个练习目录绑定 GitHub 仓库。"
        Write-Host "先去 GitHub 创建一个空仓库，然后把 HTTPS 或 SSH 地址粘贴到这里。"
        $RepoUrl = Read-Host "请输入 GitHub 仓库地址"
    }

    if (-not $RepoUrl) {
        throw "没有输入 GitHub 仓库地址，已停止。"
    }

    Invoke-Git -Arguments @("-C", $script:RepoRoot, "remote", "add", "origin", $RepoUrl)
}

function Ensure-MainBranch {
    $branch = Get-GitOutput -Arguments @("-C", $script:RepoRoot, "branch", "--show-current")
    if ($branch -ne "main") {
        Invoke-Git -Arguments @("-C", $script:RepoRoot, "branch", "-M", "main")
    }
}

Set-ConsoleUtf8
$script:RepoRoot = Split-Path -Parent $PSCommandPath
$script:GitExe = Find-Git

if (-not $script:GitExe) {
    Write-Host "没有找到 Git。请先安装 Git for Windows，或者安装并登录 GitHub Desktop。"
    exit 1
}

Write-Host "使用 Git：$script:GitExe"

Set-Location -LiteralPath $script:RepoRoot
Ensure-GitIgnore
Ensure-Repository
Ensure-UserIdentity
Ensure-OriginRemote
Ensure-MainBranch

Invoke-Git -Arguments @("-C", $script:RepoRoot, "add", ".")

$status = Get-GitOutput -Arguments @("-C", $script:RepoRoot, "status", "--short")
if (-not $status) {
    Write-Host "今天没有新的改动可上传。"
    exit 0
}

if (-not $Message) {
    $Message = "练习代码更新 $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

Invoke-Git -Arguments @("-C", $script:RepoRoot, "commit", "-m", $Message)

$upstream = Get-GitOutput -Arguments @("-C", $script:RepoRoot, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
if ($upstream) {
    Invoke-GitWithRetry -Arguments @("-C", $script:RepoRoot, "push")
} else {
    Invoke-GitWithRetry -Arguments @("-C", $script:RepoRoot, "push", "-u", "origin", "main")
}

Write-Host "上传完成。"
