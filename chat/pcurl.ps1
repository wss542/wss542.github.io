# =============================================================
#  Bot PC Reporter - 上报地址自动发现模块 (pcurl.ps1)
#
#  永久固定入口:  https://wss542.github.io/chat/cf_url.txt
#  该文件由 VM 上的 cloudflared_chat.py 看门狗自动维护,
#  隧道域名变化后几十秒内就会刷新, 因此 Windows 端
#  再也不需要手动改 REPORT_URL。
#
#  用法 (在 reporter 脚本顶部, 替换原来写死的 REPORT_URL 那一行):
#      [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
#      iex (irm 'https://wss542.github.io/chat/pcurl.ps1')
#      $REPORT_URL = Get-BotReportUrl
#
#  上报连续失败时 (说明隧道换地址了), 调用:
#      $REPORT_URL = Get-BotReportUrl -Force
# =============================================================

# Windows PowerShell 5.1 默认不开 TLS1.2, 不设置会连不上 GitHub
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol
} catch { }

$script:BotDiscoverySources = @(
    'https://raw.githubusercontent.com/wss542/wss542.github.io/main/chat/cf_url.txt',
    'https://wss542.github.io/chat/cf_url.txt'
)
$script:BotCachePath   = Join-Path $env:LOCALAPPDATA 'botpc_last_url.txt'
$script:BotReportUrl   = $null
$script:BotLastResolve = [datetime]::MinValue

function Resolve-BotBaseUrl {
    foreach ($src in $script:BotDiscoverySources) {
        try {
            $sep  = if ($src -like '*?*') { '&' } else { '?' }
            $bust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $txt  = Invoke-RestMethod -Uri ($src + $sep + 'nc=' + $bust) `
                        -TimeoutSec 10 -Headers @{ 'Cache-Control' = 'no-cache' }
            $base = ([string]$txt).Trim()
            if ($base -match '^https?://[^\s]+$') {
                try { Set-Content -Path $script:BotCachePath -Value $base -Encoding ASCII -Force } catch { }
                return $base.TrimEnd('/')
            }
        } catch { }
    }
    # 网络全挂 -> 退回上次成功缓存的地址
    if (Test-Path $script:BotCachePath) {
        try {
            $c = (Get-Content $script:BotCachePath -Raw).Trim()
            if ($c -match '^https?://') { return $c.TrimEnd('/') }
        } catch { }
    }
    return $null
}

function Get-BotReportUrl {
    param([switch]$Force)
    # 非强制时 5 分钟内复用上次结果, 避免每 3 秒都去拉 GitHub
    if (-not $Force -and $script:BotReportUrl -and
        ((Get-Date) - $script:BotLastResolve).TotalSeconds -lt 300) {
        return $script:BotReportUrl
    }
    $base = Resolve-BotBaseUrl
    if (-not $base) { return $script:BotReportUrl }
    $url = $base + '/chat/pcreport'
    if ($url -ne $script:BotReportUrl) {
        Write-Host ("[discover] REPORT_URL -> {0}" -f $url) -ForegroundColor Cyan
    }
    $script:BotReportUrl   = $url
    $script:BotLastResolve = Get-Date
    return $url
}

function Get-BotBaseUrl {
    param([switch]$Force)
    $u = Get-BotReportUrl -Force:$Force
    if ($u) { return $u -replace '/chat/pcreport$', '' }
    return $null
}
