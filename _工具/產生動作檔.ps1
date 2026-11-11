param([string]$Json, [string]$OutRoot)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)
$utf8bom = New-Object Text.UTF8Encoding($true)
$actRoot = Join-Path $OutRoot '動作'
$j = [IO.File]::ReadAllText($Json, [Text.Encoding]::UTF8) | ConvertFrom-Json

function Safe([string]$s) { if (-not $s) { return '_' }; ($s -replace '[\\/:*?"<>|]', '＿').Trim().TrimEnd('.') }

# existing user files: collect Robin ids already present so we never overwrite / duplicate
$existing = @{}
if (Test-Path $actRoot) {
  Get-ChildItem $actRoot -Recurse -File -Filter *.txt | ForEach-Object {
    foreach ($line in [IO.File]::ReadAllLines($_.FullName, [Text.Encoding]::UTF8)) {
      if ($line -match '^\s*(?:IF \(|WAIT \()?([A-Za-z]+\.[A-Za-z0-9]+)') { $existing[$matches[1]] = $_.FullName }
    }
  }
}

$vmZh = @{ 'Workstation' = '工作站'; 'Scripting' = '指令碼處理'; 'GoogleCognitive' = 'Google'; 'MicrosoftCognitive' = 'Microsoft'; 'IBMCognitive' = 'IBM' }
$typeZh = @{ 'String'='文字'; 'Boolean'='布林'; 'Int32'='整數'; 'Int64'='整數'; 'Double'='數值'; 'Decimal'='數值'; 'DataTable'='資料表'; 'DataRow'='資料列'; 'EncryptableObject'='文字(可加密)'; 'DateTime'='日期時間'; 'Object'='一般值'; 'CustomObject'='自訂物件' }

function ValueFor($p, $robinMod) {
  if ($p.IsEnum) { if ($p.HasDefault -and $p.Default) { return "$robinMod.$($p.EnumType).$($p.Default)" } elseif (@($p.Enum).Count) { return "$robinMod.$($p.EnumType).$(@($p.Enum)[0].Name)" } }
  if ($p.HasDefault -and "$($p.Default)" -ne '') {
    switch -regex ($p.Type) {
      '^(Boolean)$' { return "$($p.Default)" }
      '^(Int16|Int32|Int64|Double|Decimal|Single|Byte)$' { return "$($p.Default)" }
      '^(String|EncryptableObject)$' { return "`$'''$($p.Default)'''" }
    }
  }
  return '``'
}

# 只省略「選填」且預設空白的參數；必填但預設空白的(例如 Text、Title、Message)要寫出來
function SkipEmpty($p) { return ($p.Optional -and $p.HasDefault -and "$($p.Default)" -eq '' -and -not $p.IsEnum -and $p.Type -ne 'Boolean') }

# 條件動作要包在 IF (...) THEN / END，等待動作要包在 WAIT (...) FOR 秒數，否則貼不上
function Wrap($line, $a) {
  switch ($a.Kind) {
    'ConditionActionAttribute' { return "IF ($line) THEN`r`nEND" }
    'WaitActionAttribute' { return "WAIT ($line) FOR 10" }
    default { return $line }
  }
}

$csv = New-Object System.Collections.ArrayList
$written = 0; $skipped = New-Object System.Collections.ArrayList
$usedPaths = @{}

foreach ($a in ($j | Sort-Object Module, Order)) {
  $robinBase = "$($a.RobinModule).$($a.Id)"
  # folder path
  $parts = @()
  if ($a.RobinModule -eq 'Workstation' -or $a.RobinModule -eq 'Scripting') { $parts += $vmZh[$a.RobinModule] }
  else {
    $parts += $a.ModuleZh
    foreach ($c in @($a.CategoryPath)) { if ($vmZh.ContainsKey($c)) { $parts += $vmZh[$c] } elseif ($c -ne $a.RobinModule) { $parts += $c } }
  }
  $name = if ($a.Zh) { $a.Zh } elseif ($a.En) { $a.En } else { $a.Id }
  $dirRel = (($parts | ForEach-Object { Safe $_ }) -join '\')
  $leaf = Safe $name
  $keyPath = "$dirRel\$leaf"
  if ($usedPaths.ContainsKey($keyPath)) { $leaf = Safe "$name ($($a.Id))"; $keyPath = "$dirRel\$leaf" }
  $usedPaths[$keyPath] = 1

  if ($existing.ContainsKey($robinBase)) { [void]$skipped.Add("$robinBase -> $($existing[$robinBase])");
    [void]$csv.Add([pscustomobject]@{ 模組=$parts[0]; 分類=(($parts | Select-Object -Skip 1) -join ' > '); 動作=$name; Robin=$robinBase; 模式數=@($a.Selectors).Count; 檔案=($existing[$robinBase].Substring($OutRoot.Length + 1)); 備註='使用者原有檔案，未覆寫' }); continue }

  $params = @($a.Params)
  $ins = @($params | Where-Object { $_.Kind -eq 'in' })
  $outs = @($params | Where-Object { $_.Kind -eq 'out' })
  $sb = New-Object Text.StringBuilder

  $sels = @($a.Selectors)
  if ($sels.Count -eq 0) {
    $line = $robinBase
    foreach ($p in $ins) { if (-not (SkipEmpty $p)) { $line += " $($p.Name): $(ValueFor $p $a.RobinModule)" } }
    foreach ($p in $outs) { $line += " $($p.Name)=> $($p.Name)" }
    [void]$sb.AppendLine((Wrap $line $a))
  } else {
    $first = $true
    foreach ($s in $sels) {
      $argset = @{}; foreach ($x in @($s.Args)) { $argset[$x] = 1 }
      $line = "$robinBase.$($s.Name)"
      foreach ($p in $ins) { if ($argset.ContainsKey($p.Name) -and -not (SkipEmpty $p)) { $line += " $($p.Name): $(ValueFor $p $a.RobinModule)" } }
      foreach ($p in $outs) { if ($argset.ContainsKey($p.Name)) { $line += " $($p.Name)=> $($p.Name)" } }
      if (-not $first) { [void]$sb.AppendLine() }
      [void]$sb.AppendLine((Wrap $line $a))
      $first = $false
    }
  }

  $dir = Join-Path $actRoot "$dirRel\$leaf"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $file = Join-Path $dir "$leaf.txt"
  [IO.File]::WriteAllText($file, $sb.ToString(), $utf8)
  $written++
  [void]$csv.Add([pscustomobject]@{ 模組=$parts[0]; 分類=(($parts | Select-Object -Skip 1) -join ' > '); 動作=$name; Robin=$robinBase; 模式數=$sels.Count; 檔案=$file.Substring($OutRoot.Length + 1); 備註='' })
}

# ---- built-in Robin statements (not in module DLLs) ----
$builtin = @(
  @{ P='變數'; N='設定變數'; V=$true; C="SET NewVar TO `$'''值'''"; D='建立或修改變數。數字直接寫 SET N TO 5，運算式寫 SET N TO N + 1，清單寫 SET L TO [1, 2, 3]。' },
  @{ P='條件'; N='If'; V=$false; C="IF Var = `$'''值''' THEN`r`n    # 條件成立時執行`r`nEND"; D='運算子：= <> < <= > >=；文字比較也可以用 Contains、StartsWith 等。' },
  @{ P='條件'; N='Else if'; V=$false; C="IF A = 1 THEN`r`n    # ...`r`nELSE IF A = 2 THEN`r`n    # ...`r`nEND"; D='放在 IF 和 END 之間。' },
  @{ P='條件'; N='Else'; V=$false; C="IF A = 1 THEN`r`n    # ...`r`nELSE`r`n    # 其他情況`r`nEND"; D='放在 IF 和 END 之間。' },
  @{ P='條件'; N='Switch'; V=$false; C="SWITCH Var`r`n    CASE = 1`r`n        # ...`r`n    CASE = 2`r`n        # ...`r`n    DEFAULT`r`n        # ...`r`nEND"; D='依變數值分流。' },
  @{ P='迴圈'; N='迴圈'; V=$false; C="LOOP LoopIndex FROM 1 TO 10 STEP 1`r`n    # ...`r`nEND"; D='固定次數迴圈，LoopIndex 為目前次數。' },
  @{ P='迴圈'; N='For each'; V=$true; C="LOOP FOREACH CurrentItem IN List`r`n    # ...`r`nEND"; D='逐一處理清單或資料表的每個項目（資料表時 CurrentItem 為資料列）。' },
  @{ P='迴圈'; N='迴圈條件'; V=$false; C="LOOP WHILE (Counter) < (10)`r`n    # ...`r`nEND"; D='條件成立時重複執行。' },
  @{ P='迴圈'; N='結束迴圈'; V=$false; C='EXIT LOOP'; D='立即跳出目前的迴圈。' },
  @{ P='迴圈'; N='下一個迴圈'; V=$false; C='NEXT LOOP'; D='略過本次剩下的動作，進入下一次。' },
  @{ P='流程控制'; N='等候'; V=$true; C='WAIT 1'; D='等候秒數。' },
  @{ P='流程控制'; N='註解'; V=$false; C='# 這是一行註解'; D='不會執行。' },
  @{ P='流程控制'; N='區域'; V=$true; C="**REGION 區域名稱`r`n# ...`r`n**ENDREGION"; D='把動作分組摺疊，方便閱讀。' },
  @{ P='流程控制'; N='標籤'; V=$false; C='LABEL 標籤名稱'; D='搭配「移至」使用。' },
  @{ P='流程控制'; N='移至'; V=$false; C='GOTO 標籤名稱'; D='跳到指定標籤。' },
  @{ P='流程控制'; N='執行子流程'; V=$false; C='CALL 子流程名稱'; D='呼叫同一個流程裡的子流程。' },
  @{ P='流程控制'; N='結束子流程'; V=$false; C='EXIT FUNCTION'; D='結束目前子流程，回到呼叫處。' },
  @{ P='流程控制'; N='停止流程'; V=$false; C='EXIT Code: 0'; D='停止整個流程。' }
)
foreach ($b in $builtin) {
  $dir = Join-Path $actRoot "$($b.P)\$(Safe $b.N)"
  $file = Join-Path $dir "$(Safe $b.N).txt"
  if (Test-Path $file) { [void]$skipped.Add("builtin $($b.N) -> $file"); continue }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $txt = "$($b.C)`r`n"
  [IO.File]::WriteAllText($file, $txt, $utf8)
  $written++
  [void]$csv.Add([pscustomobject]@{ 模組=$b.P; 分類=''; 動作=$b.N; Robin=($b.C -split "`r`n")[0]; 模式數=0; 檔案=$file.Substring($OutRoot.Length + 1); 備註=$(if ($b.V) { '內建語法(已驗證)' } else { '內建語法(未驗證)' }) })
}

$csvPath = Join-Path $OutRoot '動作總表.csv'
if (Test-Path $csvPath) {
  Import-Csv -Path $csvPath -Encoding UTF8 | Where-Object { $_.Robin -like 'External.InvokeCloudConnector*' } | ForEach-Object { [void]$csv.Add($_) }
}

$csv | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
"written=$written skipped=$($skipped.Count)"
$skipped
