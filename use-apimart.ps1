# ============================================================
#  APIMart 一键接入脚本 (Windows PowerShell)
#  将已安装的 OpenClaw 实例的模型配置替换为 APIMart 中转
#  用法:  powershell -ExecutionPolicy Bypass -File use-apimart.ps1 [API_KEY]
# ============================================================
param(
    [string]$ApiKey
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---------- 颜色输出 ----------
function Write-Info  { param([string]$Msg) Write-Host "[INFO]  $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "[OK]    $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "[WARN]  $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "[ERROR] $Msg" -ForegroundColor Red }

# ---------- API Key ----------
if (-not $ApiKey) {
    $ApiKey = Read-Host "请输入 APIMart API Key"
}
if (-not $ApiKey) {
    Write-Err "API Key 不能为空"
    exit 1
}

# ---------- 节点选择 ----------
Write-Host ""
Write-Host "选择 APIMart 节点:"
Write-Host "  1) 国际节点 (api.apimart.ai)  — 海外用户推荐"
Write-Host "  2) 香港节点 (cn-api.apimart.ai) — 国内用户推荐"
$NodeChoice = Read-Host "请选择 [1/2, 默认 2]"
if (-not $NodeChoice) { $NodeChoice = "2" }

switch ($NodeChoice) {
    "1" { $Host_ = "api.apimart.ai" }
    default { $Host_ = "cn-api.apimart.ai" }
}
Write-Info "使用节点: $Host_"

# ---------- 构建 providers ----------
$Providers = [ordered]@{
    "apimart" = [ordered]@{
        baseUrl = "https://$Host_/v1"
        api     = "openai-completions"
        apiKey  = $ApiKey
        models  = @(
            @{ id = "gpt-5.3-codex";      name = "GPT-5.3 Codex" }
            @{ id = "gpt-5.3";            name = "GPT-5.3" }
            @{ id = "gpt-5.2";            name = "GPT-5.2" }
            @{ id = "gpt-5.1";            name = "GPT-5.1" }
            @{ id = "gpt-5";              name = "GPT-5" }
            @{ id = "deepseek-v3.2";      name = "DeepSeek V3.2" }
            @{ id = "deepseek-v3-0324";   name = "DeepSeek V3-0324" }
            @{ id = "deepseek-r1-0528";   name = "DeepSeek R1-0528" }
            @{ id = "glm-5";             name = "GLM-5" }
            @{ id = "kimi-k2.5";         name = "Kimi K2.5" }
            @{ id = "minimax-m2.5";      name = "MiniMax M2.5" }
        )
    }
    "apimart-claude" = [ordered]@{
        baseUrl = "https://$Host_"
        api     = "anthropic-messages"
        apiKey  = $ApiKey
        models  = @(
            @{ id = "claude-opus-4-6";              name = "Claude Opus 4.6" }
            @{ id = "claude-sonnet-4-6";            name = "Claude Sonnet 4.6" }
            @{ id = "claude-opus-4-5-20251101";     name = "Claude Opus 4.5" }
            @{ id = "claude-sonnet-4-5-20250929";   name = "Claude Sonnet 4.5" }
            @{ id = "claude-haiku-4-5-20251001";    name = "Claude Haiku 4.5" }
        )
    }
    "apimart-gemini" = [ordered]@{
        baseUrl = "https://$Host_/v1beta"
        api     = "google-generative-ai"
        apiKey  = $ApiKey
        models  = @(
            @{ id = "gemini-2.5-pro";              name = "Gemini 2.5 Pro" }
            @{ id = "gemini-2.5-flash";            name = "Gemini 2.5 Flash" }
            @{ id = "gemini-3.1-flash-preview";    name = "Gemini 3.1 Flash Preview" }
            @{ id = "gemini-3.1-pro-preview";      name = "Gemini 3.1 Pro Preview" }
        )
    }
}

# ---------- 默认模型 ----------
Write-Host ""
Write-Host "选择默认模型:"
Write-Host "  1) gpt-5.3          — OpenAI 最新"
Write-Host "  2) claude-sonnet-4-6 — Claude 性价比之选"
Write-Host "  3) deepseek-v3.2    — 国产高性价比"
Write-Host "  4) gemini-2.5-pro   — Google 最强"
$ModelChoice = Read-Host "请选择 [1-4, 默认 1]"
if (-not $ModelChoice) { $ModelChoice = "1" }

switch ($ModelChoice) {
    "2" { $DefaultModel = "apimart-claude/claude-sonnet-4-6" }
    "3" { $DefaultModel = "apimart/deepseek-v3.2" }
    "4" { $DefaultModel = "apimart-gemini/gemini-2.5-pro" }
    default { $DefaultModel = "apimart/gpt-5.3" }
}
Write-Info "默认模型: $DefaultModel"

# ---------- 查找 openclaw 配置 ----------
$HomeDir = $env:USERPROFILE
$AllConfigs = @()
$AllNames = @()

# 默认实例
$defaultCfg = Join-Path $HomeDir ".openclaw\openclaw.json"
if (Test-Path $defaultCfg) {
    $AllConfigs += $defaultCfg
    $AllNames += "default"
}

# 命名实例
Get-ChildItem -Path $HomeDir -Filter ".openclaw-*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $cfgPath = Join-Path $_.FullName "openclaw.json"
    if (Test-Path $cfgPath) {
        $AllConfigs += $cfgPath
        $instName = $_.Name -replace '^\.openclaw-', ''
        $AllNames += $instName
    }
}

if ($AllConfigs.Count -eq 0) {
    Write-Err "未找到任何 OpenClaw 配置文件 (~\.openclaw\openclaw.json 或 ~\.openclaw-*\openclaw.json)"
    Write-Err "请确认已安装 OpenClaw"
    exit 1
}

Write-Host ""
Write-Info "找到 $($AllConfigs.Count) 个实例:"
Write-Host "  0) 全部替换"
for ($i = 0; $i -lt $AllNames.Count; $i++) {
    Write-Host "  $($i+1)) $($AllNames[$i])  — $($AllConfigs[$i])"
}

$InstChoice = Read-Host "请选择要替换的实例 [0-$($AllConfigs.Count), 默认 0]"
if (-not $InstChoice) { $InstChoice = "0" }

$Configs = @()
if ($InstChoice -eq "0") {
    $Configs = $AllConfigs
} elseif ([int]$InstChoice -ge 1 -and [int]$InstChoice -le $AllConfigs.Count) {
    $Configs += $AllConfigs[[int]$InstChoice - 1]
} else {
    Write-Err "无效选择"
    exit 1
}

Write-Host ""
Write-Info "将替换以下配置:"
foreach ($c in $Configs) {
    Write-Host "    $c"
}

Write-Host ""
$Confirm = Read-Host "确认？[y/N]"
if ($Confirm -notmatch '^[yY]') {
    Write-Info "已取消"
    exit 0
}

# ---------- 执行替换 ----------
$Updated = 0
foreach ($cfg in $Configs) {
    # 备份
    $bakName = "$cfg.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $cfg $bakName

    try {
        $json = Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json

        # 确保 models 和 agents 路径存在
        if (-not $json.models) {
            $json | Add-Member -NotePropertyName "models" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        if (-not $json.agents) {
            $json | Add-Member -NotePropertyName "agents" -NotePropertyValue ([PSCustomObject]@{
                defaults = [PSCustomObject]@{
                    model = [PSCustomObject]@{
                        primary = ""
                    }
                }
            }) -Force
        }
        if (-not $json.agents.defaults) {
            $json.agents | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{
                model = [PSCustomObject]@{ primary = "" }
            }) -Force
        }
        if (-not $json.agents.defaults.model) {
            $json.agents.defaults | Add-Member -NotePropertyName "model" -NotePropertyValue ([PSCustomObject]@{
                primary = ""
            }) -Force
        }

        # 替换 providers 和默认模型
        $json.models | Add-Member -NotePropertyName "providers" -NotePropertyValue ([PSCustomObject]$Providers) -Force
        $json.agents.defaults.model.primary = $DefaultModel

        # 写回文件 (Depth 10 确保嵌套对象完整序列化)
        $json | ConvertTo-Json -Depth 10 | Set-Content $cfg -Encoding UTF8

        Write-Ok "已更新: $cfg"
        $Updated++
    }
    catch {
        Write-Err "更新失败: $cfg ($_)"
    }
}

Write-Host ""
if ($Updated -gt 0) {
    Write-Ok "完成! 已更新 $Updated 个配置文件"
    Write-Host ""
    Write-Warn "请重启 OpenClaw 使配置生效:"
    Write-Host "    openclaw stop && openclaw start"
    Write-Host ""
    Write-Info "备份文件保存在原目录 (.bak.* 后缀)，可随时恢复"
} else {
    Write-Err "没有配置被更新"
}
