# 比對實測動作.ps1
# 把「正式流程」「demo」資料夾裡實際能執行的流程用到的動作名稱與參數，拿去跟「動作」資料夾的動作庫比對，
# 列出動作庫裡找不到的名稱、或參數名稱不一樣的地方。
# 用法：在 PowerShell 執行  .\_工具\比對實測動作.ps1  （可加 -流程資料夾 指定其他資料夾，用分號隔開）
param(
    [string]$流程資料夾 = ((Join-Path $PSScriptRoot '..\正式流程') + ';' + (Join-Path $PSScriptRoot '..\demo')),
    [string]$動作資料夾 = (Join-Path $PSScriptRoot '..\動作')
)

$callPattern = '^\s*(?:WAIT\s*\(|IF\s+(?:NOT\s+)?\(|ELSE IF\s+\()?\s*([A-Z]\w*\.[A-Z]\w*(?:\.[A-Z]\w*)?)(?:\s|\)|$)'
# 不比對：列舉值、變數屬性(例如 X.RowsCount)、雲端連接器(定義在雲端，動作庫本來就沒有)
$skip = '^(Text\.TrimOption|Variables\.SortDirection|WebAutomation\.(ClickType|RectangleEdgePoint|PopulateTextMode|ElementState|DetailsType))|\.(RowsCount|Count|Length|ColumnNames)$|^External\.InvokeCloudConnector$'

function Get-Params([string]$line) {
    # 參數名稱：空白後面接 名稱: 或 名稱=>（不含 $'''...''' 裡的文字）
    $clean = [regex]::Replace($line, "\$'''.*?'''", "''", 'Singleline')
    [regex]::Matches($clean, '\s([A-Za-z@][\w@]*)(?::|=>)\s') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
}

# 1. 動作庫：完整名稱 -> 參數集合
$lib = @{}
Get-ChildItem $動作資料夾 -Recurse -Filter *.txt | ForEach-Object {
    $file = $_.FullName
    Get-Content $file -Encoding UTF8 | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') } | ForEach-Object {
        if ($_ -match $callPattern) {
            $lib[$Matches[1]] = @{ Params = @(Get-Params $_); File = $file.Substring((Resolve-Path $動作資料夾).Path.Length + 1) }
        }
    }
}

# 2. 實測流程：完整名稱 -> 參數集合、出處
$used = @{}
Get-ChildItem ($流程資料夾 -split ';' | Where-Object { Test-Path $_ }) -Recurse -Filter *.txt | ForEach-Object {
    $file = $_.Name
    $text = Get-Content $_.FullName -Raw -Encoding UTF8
    $code = ($text -split '# \[ControlRepository\]')[0]
    foreach ($line in ($code -split "`n")) {
        if ($line -match $callPattern) {
            $name = $Matches[1]
            if ($name -match $skip) { continue }
            if (-not $used.ContainsKey($name)) { $used[$name] = @{ Params = @(); Files = @() } }
            $used[$name].Params = @($used[$name].Params + (Get-Params $line) | Sort-Object -Unique)
            if ($used[$name].Files -notcontains $file) { $used[$name].Files += $file }
        }
    }
}

# 3. 比對
$libBase = @{}
foreach ($k in $lib.Keys) { $p = $k.Split('.'); $libBase["$($p[0]).$($p[1])"] = $true }
$report = foreach ($name in ($used.Keys | Sort-Object)) {
    $u = $used[$name]
    if ($lib.ContainsKey($name)) {
        $missing = @($u.Params | Where-Object { $lib[$name].Params -notcontains $_ })
        if ($missing.Count) {
            [pscustomobject]@{ 結果 = '參數不同'; 實測寫法 = $name; 說明 = '動作庫沒有參數：' + ($missing -join ', '); 動作庫檔案 = $lib[$name].File; 出處 = $u.Files -join ', ' }
        }
    } else {
        $p = $name.Split('.')
        $similar = @($lib.Keys | Where-Object { $_ -like "$($p[0]).$($p[1])*" -or ($p.Count -gt 2 -and $_ -like "$($p[0]).*" -and $_.EndsWith(".$($p[2])")) } | Sort-Object)
        [pscustomobject]@{ 結果 = '動作庫找不到'; 實測寫法 = $name; 說明 = '動作庫類似的寫法：' + $(if ($similar) { $similar -join ' / ' } else { '（無）' }); 動作庫檔案 = $(if ($similar) { $lib[$similar[0]].File } else { '' }); 出處 = $u.Files -join ', ' }
    }
}

Write-Host "實測流程用到 $($used.Count) 種動作寫法；動作庫共 $($lib.Count) 種。" -ForegroundColor Cyan
if ($report) {
    $report | Format-List
    $out = Join-Path $PSScriptRoot '比對結果.csv'
    $report | Export-Csv $out -NoTypeInformation -Encoding UTF8
    Write-Host "共 $(@($report).Count) 筆差異，已存到 $out" -ForegroundColor Yellow
} else {
    Write-Host '全部一致。' -ForegroundColor Green
}
