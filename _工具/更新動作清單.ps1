# 更新動作清單：PAD 更新後執行一次，只會「新增」沒有的動作，不會覆寫既有檔案
# 用法：在 PowerShell 執行  powershell -ExecutionPolicy Bypass -File ".\_工具\更新動作清單.ps1"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$json = Join-Path $env:TEMP 'pad_actions.json'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here '擷取動作.ps1') -OutJson $json
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here '產生動作檔.ps1') -Json $json -OutRoot $root