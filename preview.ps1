#requires -Version 5.1
[CmdletBinding()]
param([switch]$Empty)

$ErrorActionPreference = 'Stop'
# Source preview uses the same UI and storage code as the packaged app.
# Keep its data and settings separate from the installed application.
$previewRoot = Join-Path $PSScriptRoot '.preview'
$env:DAIBAN_DATA_DIR = Join-Path $previewRoot 'data'
$env:DAIBAN_CONFIG_DIR = Join-Path $previewRoot 'config'
$env:DAIBAN_PREVIEW = '1'
[void][IO.Directory]::CreateDirectory($env:DAIBAN_DATA_DIR)
[void][IO.Directory]::CreateDirectory($env:DAIBAN_CONFIG_DIR)

$todos = Join-Path $env:DAIBAN_DATA_DIR 'todos.json'
if (-not $Empty -and -not (Test-Path -LiteralPath $todos)) {
    $now = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    $titles = @('整理今天想做的三件小事', '给新项目留一点专注的时间', '下班后，去散个步', '写下想法，让脑袋轻一点', '打开 TodoDesk，开始新的一天')
    $items = for ($i = 0; $i -lt $titles.Count; $i++) {
        [ordered]@{
            id = [guid]::NewGuid().ToString('N')
            title = $titles[$i]
            completed = ($i -ge 3)
            createdAt = $now - ($i * 60000)
            completedAt = $(if ($i -ge 3) { $now } else { $null })
        }
    }
    $json = @{ version = 1; items = @($items) } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($todos, $json, [Text.UTF8Encoding]::new($false))
}
try {
    & (Join-Path $PSScriptRoot 'app\DaiBan.ps1')
}
catch {
    Add-Type -AssemblyName PresentationFramework
    [IO.File]::WriteAllText((Join-Path $previewRoot 'preview-error.log'), $_.ToString())
    [void][Windows.MessageBox]::Show($_.Exception.Message, 'TodoDesk preview')
    exit 1
}
