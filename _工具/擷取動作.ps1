param(
  [string]$PadRoot = "${env:ProgramFiles(x86)}\Power Automate Desktop",
  [string]$OutJson
)
$ErrorActionPreference = 'Continue'
$global:PadRootG = $PadRoot; $global:Resolving = @{}
[AppDomain]::CurrentDomain.add_AssemblyResolve({ param($s,$e)
  $n = ($e.Name -split ',')[0]; if ($n -like '*.resources' -or $global:Resolving[$n]) { return $null }; $global:Resolving[$n] = $true
  foreach ($d in @($global:PadRootG, (Join-Path $global:PadRootG 'dotnet'))) { $p = Join-Path $d "$n.dll"; if (Test-Path $p) { return [Reflection.Assembly]::LoadFrom($p) } }
  return $null
})
$zh = [Globalization.CultureInfo]::GetCultureInfo('zh-Hant')
$inv = [Globalization.CultureInfo]::InvariantCulture

function Get-AttrArg($cad, $name) {
  foreach ($na in $cad.NamedArguments) { if ($na.MemberName -eq $name) { return $na.TypedValue.Value } }
  return $null
}

$results = New-Object System.Collections.ArrayList
$seen = @{}
$dlls = Get-ChildItem $PadRoot -Filter 'Microsoft.Flow.RPA.Desktop.Modules.*.Actions.dll'
foreach ($dll in $dlls) {
  $modName = $dll.Name -replace '^Microsoft\.Flow\.RPA\.Desktop\.Modules\.','' -replace '\.Actions\.dll$',''
  [Console]::Error.WriteLine("DLL " + $dll.Name)
  try { $asm = [Reflection.Assembly]::LoadFrom($dll.FullName) } catch { Write-Warning "load fail $($dll.Name)"; continue }
  $rn = $asm.GetManifestResourceNames() | Where-Object { $_ -like '*Properties.Resources.resources' } | Select-Object -First 1
  if (-not $rn) { $rn = $asm.GetManifestResourceNames() | Where-Object { $_ -like '*.resources' } | Select-Object -First 1 }
  $rm = $null; if ($rn) { $rm = New-Object Resources.ResourceManager(($rn -replace '\.resources$',''), $asm) }
  $L = { param($key) if (-not $rm) { return $null }; try { $v = $rm.GetString($key, $zh) } catch { $v = $null }; if (-not $v) { try { $v = $rm.GetString($key, $inv) } catch {} }; return $v }
  $E = { param($key) if (-not $rm) { return $null }; try { return $rm.GetString($key, $inv) } catch { return $null } }
  if (-not $script:KeyCache) { $script:KeyCache = @{} }; $kc = @{}; if ($rm) { try { $rm.GetResourceSet($inv,$true,$true) | ForEach-Object { $kc[$_.Key] = 1 } } catch {} }; $script:KeyCache[$dll.Name] = $kc
  $modZh = & $L "$($modName)_FriendlyName"; if (-not $modZh) { $modZh = $modName }

  try { $types = $asm.GetTypes() } catch [Reflection.ReflectionTypeLoadException] { $types = $_.Exception.Types | Where-Object { $_ } }
  # selectors grouped by action type
  $selMap = @{}
  foreach ($t in $types) {
    if ($t.IsAbstract) { continue }
    $bt = $t.BaseType
    if ($bt -and $bt.IsGenericType -and $bt.Name -like 'ActionSelector*') {
      $target = $bt.GetGenericArguments()[0].FullName
      try { $o = [Activator]::CreateInstance($t) } catch { continue }
      $args2 = @(); try { $args2 = @($o.Arguments | ForEach-Object { "$_" }) } catch {}
      $vis = @(); try { $vis = @($o.VisibleArguments | ForEach-Object { "$_" }) } catch {}
      $cons = @(); try { $cons = @($o.Constraints.Keys | ForEach-Object { "$_" }) } catch {}
      if (-not $selMap.ContainsKey($target)) { $selMap[$target] = New-Object System.Collections.ArrayList }
      [void]$selMap[$target].Add([pscustomobject]@{ Name = $o.ActionName; Args = $args2; Visible = $vis; Constrained = $cons })
    }
  }

  foreach ($t in $types) {
    if ($t.IsAbstract -or -not $t.BaseType) { continue }
    $isAction = $false; $b = $t.BaseType
    while ($b) { if ($b.Name -eq 'ActionBase') { $isAction = $true; break }; $b = $b.BaseType }
    if (-not $isAction) { continue }
    $cads = @(); try { $cads = @($t.GetCustomAttributesData()) } catch {}
    $aa = $cads | Where-Object { $_.AttributeType.Name -eq 'ActionAttribute' } | Select-Object -First 1
    $id = $null; $cat = $null; $order = 999; $hidden = $false
    if ($aa) { $id = Get-AttrArg $aa 'Id'; $cat = Get-AttrArg $aa 'Category'; $o2 = Get-AttrArg $aa 'Order'; if ($o2 -ne $null) { $order = $o2 }; if ((Get-AttrArg $aa 'Hidden') -eq $true -or (Get-AttrArg $aa 'IsHidden') -eq $true) { $hidden = $true } }
    if (-not $id -and $aa) { $id = Get-AttrArg $aa 'Name' }; if (-not $id) { $id = $t.Name }
    $vm = $cads | Where-Object { $_.AttributeType.Name -eq 'VirtualModuleAttribute' } | Select-Object -First 1
    $robinMod = $modName; $vmName = $null
    if ($vm) { $vmName = Get-AttrArg $vm 'Name'; if ($vmName) { $robinMod = $vmName } }
    $obsolete = [bool]($cads | Where-Object { $_.AttributeType.Name -match 'Obsolete|Deprecated' })
    $throws = @($cads | Where-Object { $_.AttributeType.Name -eq 'ThrowsAttribute' } | ForEach-Object { "$($_.ConstructorArguments[0].Value)" })

    $allKeys = $script:KeyCache[$dll.Name]
    $rp = $null
    $cands = @($id, "$($id)Base", $t.Name, ($t.Name -replace 'Action$',''), "$(($t.Name -replace 'Action$',''))Base")
    if ($cat) { $cands += @("$($cat)_$($id)", "$($cat)_$($t.Name)") }
    foreach ($cd in $cands) { if ($allKeys.ContainsKey("$($cd)_FriendlyName")) { $rp = $cd; break } }
    if (-not $rp) { $hit = $allKeys.Keys | Where-Object { $_ -match "(^|_)$([regex]::Escape($id))_FriendlyName$" -and ($_ -split '_').Count -le 3 } | Select-Object -First 1; if ($hit) { $rp = $hit -replace '_FriendlyName$','' } }
    if (-not $rp) { $rp = $id }
    $catPath = @()
    if ($vmName) { $vz = & $L "$($vmName)_FriendlyName"; if (-not $vz) { $vz = & $L "Category_$($vmName)_FriendlyName" }; if (-not $vz) { $vz = $vmName }; $catPath += $vz }
    if ($cat) { foreach ($c in ($cat -split '\.')) { $cz = & $L "Category_$($c)_FriendlyName"; if (-not $cz) { $cz = $c }; $catPath += $cz } }

    $params = New-Object System.Collections.ArrayList
    foreach ($p in $t.GetProperties()) {
      $pc = @(); try { $pc = @($p.GetCustomAttributesData()) } catch {}
      $ia = $pc | Where-Object { $_.AttributeType.Name -eq 'InputArgumentAttribute' } | Select-Object -First 1
      $oa = $pc | Where-Object { $_.AttributeType.Name -eq 'OutputArgumentAttribute' } | Select-Object -First 1
      if (-not $ia -and -not $oa) { continue }
      $dv = $pc | Where-Object { $_.AttributeType.Name -eq 'DefaultValueAttribute' } | Select-Object -First 1
      $def = $null; $hasDef = $false
      if ($dv) { $hasDef = $true; $def = $dv.ConstructorArguments[0].Value }
      $pt = $p.PropertyType
      $enumVals = @()
      $isEnum = $false; try { $isEnum = $pt.IsEnum } catch {}
      if ($isEnum) {
        foreach ($en in [Enum]::GetNames($pt)) { $ez = & $L "$($pt.Name)_$($en)_FriendlyName"; $enumVals += [pscustomobject]@{ Name = $en; Zh = $ez } }
        if ($hasDef) { try { $def = [Enum]::GetName($pt, $def) } catch {} }
      }
      $porder = 999; $a2 = if ($ia) { $ia } else { $oa }; $po = Get-AttrArg $a2 'Order'; if ($po -ne $null) { $porder = $po }
      $optional = (Get-AttrArg $a2 'Optional') -eq $true
      $tn = $pt.Name; if ($pt.IsGenericType) { $tn = ($pt.Name -replace '`.*','') + '<' + (($pt.GetGenericArguments() | ForEach-Object { $_.Name }) -join ',') + '>' }
      [void]$params.Add([pscustomobject]@{
        Name = $p.Name; Kind = $(if ($ia) { 'in' } else { 'out' }); Type = $tn; IsEnum = $isEnum; EnumType = $pt.Name
        Enum = $enumVals; HasDefault = $hasDef; Default = "$def"; Order = $porder; Optional = $optional
        Zh = (& $L "$($rp)_$($p.Name)_FriendlyName"); DescZh = (& $L "$($rp)_$($p.Name)_Description")
      })
    }
    $sels = @(); if ($selMap.ContainsKey($t.FullName)) { $sels = @($selMap[$t.FullName] | ForEach-Object {
      [pscustomobject]@{ Name = $_.Name; Args = $_.Args; Visible = $_.Visible; Constrained = $_.Constrained; DescZh = $(if ($v = & $L "$($_.Name)_Description") { $v } elseif ($cat) { & $L "$($cat)_$($_.Name)_Description" }); SummaryZh = $(if ($v = & $L "$($_.Name)_Summary") { $v } elseif ($cat) { & $L "$($cat)_$($_.Name)_Summary" }) } }) }
    $key = "$robinMod.$id"
    if ($seen.ContainsKey($key)) { continue }; $seen[$key] = 1
    [void]$results.Add([pscustomobject]@{
      Module = $modName; ModuleZh = $modZh; RobinModule = $robinMod; Id = $id; Class = $t.FullName; CategoryPath = $catPath; Order = $order
      Zh = (& $L "$($rp)_FriendlyName"); En = (& $E "$($rp)_FriendlyName"); DescZh = (& $L "$($rp)_Description"); SummaryZh = (& $L "$($rp)_Summary"); ResPrefix = $rp
      Params = @($params | Sort-Object Order); Selectors = $sels; Throws = $throws; Obsolete = $obsolete; Hidden = $hidden
    })
  }
}
$results | ConvertTo-Json -Depth 8 | Out-File -FilePath $OutJson -Encoding utf8
"actions: $($results.Count)"
