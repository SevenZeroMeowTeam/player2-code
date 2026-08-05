# ============================================================
# DeepSeek R1 连通性测试（Windows PowerShell 版）
# 等价于 deploy/test-ai.sh
# 用法：先用记事本编辑项目根目录 .env，填入 AI_API_KEY=sk-xxx
#       然后在 PowerShell 里运行： .\deploy\test-ai.ps1
# ============================================================
param(
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"

# 定位项目根
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")

# 优先使用根目录 .env，其次 backend/.env
if (-not $EnvFile) {
    if (Test-Path (Join-Path $ProjectRoot ".env")) {
        $EnvFile = Join-Path $ProjectRoot ".env"
    } elseif (Test-Path (Join-Path $ProjectRoot "backend\.env")) {
        $EnvFile = Join-Path $ProjectRoot "backend\.env"
    } else {
        Write-Error "找不到 .env 文件。请先把 .env.example 复制为 .env 并填入 AI_API_KEY。"
        exit 1
    }
}
Write-Host "# 载入 $EnvFile" -ForegroundColor Cyan

# 解析 .env（忽略注释行，支持 KEY=VAL）
Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $eqIdx = $line.IndexOf("=")
        $k = $line.Substring(0, $eqIdx).Trim()
        $v = $line.Substring($eqIdx + 1).Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($k, $v, "Process")
    }
}

$AI_API_URL = [Environment]::GetEnvironmentVariable("AI_API_URL", "Process")
$AI_API_KEY = [Environment]::GetEnvironmentVariable("AI_API_KEY", "Process")
$MODEL = [Environment]::GetEnvironmentVariable("AI_MODEL", "Process")
if (-not $MODEL) { $MODEL = "deepseek-reasoner" }

if (-not $AI_API_URL) { Write-Error "需要在 .env 中设置 AI_API_URL (如 https://ai.bbsmc.org.cn/v1)"; exit 1 }
if (-not $AI_API_KEY -or $AI_API_KEY.StartsWith("sk-xxx") -or $AI_API_KEY -like "sk-xxxx*") {
    Write-Error "需要在 .env 中设置真实的 AI_API_KEY (sk- 开头，不能是占位符)"
    exit 1
}

# 双目标回退列表
$urls = @($AI_API_URL)
if ($AI_API_URL -like "*ai.bbsmc.org.cn*") {
    $urls += "https://api.deepseek.com/v1"
}

$bodyHash = @{
    model      = $MODEL
    messages   = @(
        @{ role = "system"; content = "你是一个 JSON 输出器，只输出 {`"ok`":true}" },
        @{ role = "user";   content = "输出 {`"ok`":true}" }
    )
    max_tokens = 200
}
$bodyJson = $bodyHash | ConvertTo-Json -Depth 5 -Compress

Write-Host ""
Write-Host "======== DeepSeek R1 连通性测试 ========" -ForegroundColor Yellow

function Test-Endpoint([string]$baseUrl) {
    $fullUrl = "$baseUrl/chat/completions"
    $maskedKey = $AI_API_KEY.Substring(0, [Math]::Min(8, $AI_API_KEY.Length)) + "..." + $AI_API_KEY.Substring($AI_API_KEY.Length - 4)
    Write-Host "Endpoint : $fullUrl"
    Write-Host "Model    : $MODEL"
    Write-Host "Key      : $maskedKey"
    Write-Host ""

    $headers = @{
        "Authorization" = "Bearer $AI_API_KEY"
        "Content-Type"  = "application/json"
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-RestMethod -Uri $fullUrl -Method Post -Headers $headers -Body $bodyJson -TimeoutSec 120
        $sw.Stop()
        Write-Host ("HTTP 耗时 : {0} ms" -f $sw.ElapsedMilliseconds) -ForegroundColor Green
        Write-Host ""

        $choice = $resp.choices[0].message
        $content = if ($choice.content) { $choice.content } else { "" }
        $think = if ($choice.reasoning_content) { $choice.reasoning_content } elseif ($choice.thinking_content) { $choice.thinking_content } else { "" }
        $usage = $resp.usage | ConvertTo-Json -Depth 5 -Compress

        Write-Host ("usage  : {0}" -f $usage)
        if ($think) {
            $thinkPreview = if ($think.Length -gt 200) { $think.Substring(0, 200) + "..." } else { $think }
            Write-Host ("thinking({0}chars): {1}" -f $think.Length, $thinkPreview)
        }
        $contentPreview = if ($content.Length -gt 400) { $content.Substring(0, 400) } else { $content }
        Write-Host ("content ({0}chars): {1}" -f $content.Length, $contentPreview)
        Write-Host ""
        Write-Host "若以上有 usage + content 非空，则当前 API 网关 + DeepSeek R1 配置正确。" -ForegroundColor Green
        return $true
    } catch {
        $sw.Stop()
        Write-Host ("HTTP 耗时 : {0} ms" -f $sw.ElapsedMilliseconds) -ForegroundColor Red
        Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            try {
                $errObj = $_.ErrorDetails.Message | ConvertFrom-Json
                Write-Host ("详情  : {0}" -f ($errObj | ConvertTo-Json -Depth 5 -Compress)) -ForegroundColor Red
            } catch {
                Write-Host ("详情  : {0}" -f $_.ErrorDetails.Message) -ForegroundColor Red
            }
        }
        return $false
    }
}

for ($i = 0; $i -lt $urls.Count; $i++) {
    $ok = Test-Endpoint $urls[$i]
    if ($ok) {
        [Environment]::SetEnvironmentVariable("AI_API_URL", $urls[$i], "Process")
        Write-Host ("最终使用 AI_API_URL={0}" -f $urls[$i]) -ForegroundColor Cyan
        exit 0
    }
    if ($i -lt $urls.Count - 1) {
        Write-Host ("`n# 上一个网关失败，回退到: {0}`n" -f $urls[$i + 1]) -ForegroundColor Yellow
    }
}

Write-Host "`n所有 AI 网关均失败。请检查：" -ForegroundColor Red
Write-Host "  1. AI_API_KEY 是否正确，余额是否充足"
Write-Host "  2. 网络是否能访问 ai.bbsmc.org.cn 或 api.deepseek.com"
Write-Host "  3. 如在中国大陆，官方 api.deepseek.com 可能需要代理"
exit 1
