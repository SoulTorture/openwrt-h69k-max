<#
.SYNOPSIS
    把 H69K-MAX 固件编译工程一键推送到 GitHub, 然后在云端 Actions 编译。

.DESCRIPTION
    本机不需要 Linux —— OpenWrt/LEDE 无法在 Windows 上编译 (需要大小写敏感的
    文件系统与 POSIX 工具链)。本脚本只负责把工程推到 GitHub, 由 GitHub 的
    Ubuntu runner 完成编译。

    脚本会:
      1. 检查 git / gh 环境 (缺失时提示用 winget 安装)
      2. git init + 提交本目录
      3. 用 gh 创建仓库并推送 (若已安装并登录 gh)
      4. 触发 Build OpenWrt H69K-MAX workflow

.EXAMPLE
    .\scripts\build-cloud.ps1 -RepoName openwrt-h69k-max

.EXAMPLE
    # 只做本地提交, 自己手动建仓库推送
    .\scripts\build-cloud.ps1 -SkipCreate -SkipTrigger
#>
[CmdletBinding()]
param(
    [string]$RepoName = 'openwrt-h69k-max',
    [ValidateSet('public', 'private')]
    [string]$Visibility = 'public',
    [string]$Kernel = '6.18',
    [string]$RootfsMb = '4020',
    [switch]$SkipCreate,
    [switch]$SkipTrigger
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text){ Write-Host "  [!]  $Text" -ForegroundColor Yellow }

# --- 定位工程根目录 (本脚本位于 <root>\scripts\) ---
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root 'config\h69k-max.config'))) {
    throw "未找到 config\h69k-max.config, 请把本脚本放在工程根目录的 scripts\ 下。当前根目录: $Root"
}
Write-Step "工程目录"
Write-Host "  $Root"

# --- 1. 环境检查 ---
Write-Step "环境检查"

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Warn2 "未检测到 git。"
    Write-Host @"
  请任选一种方式安装, 然后重新运行本脚本:
    winget install --id Git.Git -e --source winget
    或下载: https://git-scm.com/download/win
"@
    throw "缺少 git"
}
Write-Ok "git: $(git --version)"

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) { Write-Ok "gh: $(gh --version | Select-Object -First 1)" }
else { Write-Warn2 "未检测到 gh (GitHub CLI)。未安装则 -SkipCreate/-SkipTrigger 需手动操作, 安装: winget install --id GitHub.cli -e" }

# --- 2. git init + commit ---
Write-Step "初始化仓库并提交"
Push-Location $Root
try {
    if (-not (Test-Path '.git')) {
        git init | Out-Null
        git branch -M main 2>$null | Out-Null
        Write-Ok "已 git init"
    } else {
        Write-Ok "已存在 .git, 复用"
    }

    # 只提交本工程需要的文件, 排除临时/导出目录
    $excludes = @('out/', '*.log', '*.img', '*.img.gz', '*.itb', '*.bin')
    $gitignore = Join-Path $Root '.gitignore'
    if (-not (Test-Path $gitignore)) {
        @"
# 编译产物与临时文件
out/
*.log
*.img
*.img.gz
*.itb
*.bin
bin/
tmp/
"@ | Set-Content -Path $gitignore -Encoding utf8
        Write-Ok "已生成 .gitignore"
    }

    git add -A
    $status = git status --porcelain
    if ($status) {
        git -c user.name='h69k-builder' -c user.email='h69k-builder@local' `
            commit -m "H69K-MAX OpenWrt cloud build (LEDE, MT7916 + RM520N-GL)" | Out-Null
        Write-Ok "已提交变更"
    } else {
        Write-Ok "无变更需要提交"
    }

    # --- 3. 创建远端仓库并推送 ---
    if (-not $SkipCreate) {
        if (-not $gh) {
            Write-Warn2 "缺少 gh, 跳过自动建仓库。请手动执行:"
            Write-Host "    git remote add origin https://github.com/<你的用户名>/$RepoName.git"
            Write-Host "    git push -u origin main"
        } else {
            Write-Step "创建/推送 GitHub 仓库"
            $hasRemote = (git remote) -contains 'origin'
            if (-not $hasRemote) {
                gh repo create $RepoName "--$Visibility" --source=. --remote=origin --push
                Write-Ok "已创建并推送 $RepoName"
            } else {
                git push -u origin main
                Write-Ok "已推送到已有 origin"
            }
        }
    } else {
        Write-Warn2 "SkipCreate: 请自行创建并推送仓库"
    }

    # --- 4. 触发云编译 ---
    if (-not $SkipTrigger) {
        if (-not $gh) {
            Write-Warn2 "缺少 gh, 请到 GitHub 网页: Actions -> Build OpenWrt H69K-MAX -> Run workflow"
        } else {
            Write-Step "触发 GitHub Actions 编译"
            gh workflow run "build-h69k-max.yml" `
                -f "kernel=$Kernel" `
                -f "rootfs_size_mb=$RootfsMb" `
                -f "use_cache=true" `
                -f "make_release=true"
            Write-Ok "已触发。查看进度: gh run watch  或  gh run list"
            Start-Sleep -Seconds 4
            gh run list --workflow="build-h69k-max.yml" --limit 3
        }
    } else {
        Write-Warn2 "SkipTrigger: 未触发编译"
    }
}
finally {
    Pop-Location
}

Write-Host @"

下一步:
  1. 打开仓库的 Actions 页面, 等待 "Build OpenWrt H69K-MAX" 完成 (约 1.5-4 小时)
  2. 在 Release / Artifacts 下载:
       openwrt-*-rockchip-armv8-hinlink_opc-h69k-*squashfs-sysupgrade.img.gz
  3. 刷机见 README.md "刷机" 章节 (TF 卡先试, 再刷 eMMC)
"@ -ForegroundColor Gray
