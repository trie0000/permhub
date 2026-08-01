<#
.SYNOPSIS
  src/*.pa.yaml をソリューション経由で既存のキャンバスアプリに反映する（Windows / PowerShell）。

.DESCRIPTION
  画面ごとの貼り付けをやめ、コマンドだけでアプリを更新して公開する。

    export → 中の .msapp を YAML に開く → 画面を差し替える → pack → 詰め直す → import

  Premium も Entra ID のアプリ登録も要らない。pac の対話ログインだけで動く。

.PARAMETER SolutionName
  ソリューションの一意名（表示名ではない）。`pac solution list` の Unique Name。

.PARAMETER SrcDir
  差し替え元。既定はこのスクリプトの 1 つ上の src。

.PARAMETER Screens
  差し替える画面。既定は ScrHome / ScrUser / ScrReq。

.PARAMETER NoImport
  import を行わず、詰め直した zip を作るところで止める。中身を確認したいとき。

.EXAMPLE
  .\setup\deploy.ps1 -SolutionName permhub

.NOTES
  初回だけ、アプリをソリューションに入れておく必要がある。docs/cli.md を参照。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SolutionName,
  [string]$SrcDir,
  [string[]]$Screens = @('ScrHome', 'ScrUser', 'ScrReq'),
  [switch]$NoImport
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
if (-not $SrcDir) { $SrcDir = Join-Path $Root 'src' }

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

# ---- 0. 前提の確認 ---------------------------------------------------------
Write-Step '前提を確認'

if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
  throw @'
pac (Power Platform CLI) が見つからない。入れ方は 2 通り。

[A] .NET SDK 経由（検証済みの構成。pac が最新になる）

    1. https://aka.ms/dotnet/download から .NET SDK を入れる
       ※ ランタイムだけでは足りない。"No .NET SDKs were found" はこれが原因
    2. dotnet tool install --global Microsoft.PowerApps.CLI.Tool

[B] MSI（.NET SDK が要らない）

    https://aka.ms/PowerAppsCLI から powerapps-cli MSI を入れる
    ※ 配布されている版が古いことがある。入れたあと下のバージョン確認が通るか見る

どちらでも、入れたら新しいターミナルを開いて認証する:

    pac auth create --name permhub
'@
}

# pac が古いと --layout SourceCode が無く、このスクリプトは動かない。
# バージョン番号ではなくヘルプに SourceCode があるかで判定する（版によって番号体系が違うため）
$packHelp = pac canvas pack 2>&1 | Out-String
if ($packHelp -notmatch 'SourceCode') {
  throw @'
pac が古い。`pac canvas pack` に --layout SourceCode が無い。

    pac --version

で版を確認し、新しいものを入れ直す:

    dotnet tool update --global Microsoft.PowerApps.CLI.Tool
'@
}

$auth = pac auth list 2>&1 | Out-String
if ($auth -match 'No profiles were found') {
  throw "認証プロファイルが無い。`pac auth create --name permhub` を実行する。"
}

foreach ($s in $Screens) {
  $p = Join-Path $SrcDir "$s.pa.yaml"
  if (-not (Test-Path $p)) { throw "見つからない: $p" }
}

# ---- 1. YAML の重複プロパティを落とす --------------------------------------
# 同じ Properties ブロックに同名のプロパティが 2 つあると、取り込み時に
# `PA1001 ... Duplicate name 'Fill'` で失敗する。pac canvas pack は素通しするので
# ここで見る（setup/check-yaml.py と同じ判定を PowerShell で行う）。
Write-Step 'YAML を検査'

$dupTotal = 0
foreach ($s in $Screens) {
  $path = Join-Path $SrcDir "$s.pa.yaml"
  $indent = -1
  $seen = @{}
  $n = 0
  foreach ($line in [System.IO.File]::ReadAllLines($path)) {
    $n++
    if ($line -match '^(\s*)Properties:\s*$') {
      $indent = $Matches[1].Length + 2
      $seen = @{}
      continue
    }
    if ($indent -lt 0) { continue }
    if ($line -notmatch '^(\s*)([A-Za-z][A-Za-z0-9_.]*):(\s|$)') { continue }
    $col = $Matches[1].Length
    $key = $Matches[2]
    if ($col -ne $indent) {
      if ($col -lt $indent) { $indent = -1 }
      continue
    }
    if ($seen.ContainsKey($key)) {
      Write-Warn "$s.pa.yaml : $n 行目 重複したプロパティ '$key'（最初は $($seen[$key]) 行目）"
      $dupTotal++
    }
    $seen[$key] = $n
  }
}
if ($dupTotal -gt 0) {
  throw "重複 $dupTotal 件。このまま取り込むと PA1001 で失敗する。直してから再実行する。"
}
Write-Host '  重複なし'

# ---- 2. 作業フォルダ -------------------------------------------------------
$Work = Join-Path ([System.IO.Path]::GetTempPath()) "permhub-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $Work -Force | Out-Null
$zipIn = Join-Path $Work 'sol.zip'
$ext = Join-Path $Work 'sol'
$zipOut = Join-Path $Work 'sol-mod.zip'

# ---- 3. エクスポート -------------------------------------------------------
Write-Step "ソリューション '$SolutionName' をエクスポート"
pac solution export --path $zipIn --name $SolutionName --overwrite
if ($LASTEXITCODE -ne 0) { throw "エクスポートに失敗した。一意名を確認する（pac solution list）。" }

Expand-Archive -Path $zipIn -DestinationPath $ext -Force

$msapp = Get-ChildItem -Path (Join-Path $ext 'CanvasApps') -Filter '*.msapp' -File |
         Select-Object -First 1
if (-not $msapp) { throw "CanvasApps に .msapp が無い。アプリがソリューションに入っていない。" }
Write-Host "  対象: $($msapp.Name)"

# ---- 4. 画面を差し替える ---------------------------------------------------
Write-Step '画面を差し替え'
$srcOut = Join-Path $Work 'unpacked'
pac canvas unpack --msapp $msapp.FullName --sources $srcOut --layout SourceCode
if ($LASTEXITCODE -ne 0) { throw '.msapp の展開に失敗した。' }

foreach ($s in $Screens) {
  $from = Join-Path $SrcDir "$s.pa.yaml"
  $to = Join-Path $srcOut "Src\$s.pa.yaml"
  if (-not (Test-Path $to)) { Write-Warn "$s はアプリ側に無い。新しい画面として入る" }
  Copy-Item $from $to -Force
  Write-Host "  $s.pa.yaml"
}

pac canvas pack --sources $srcOut --msapp $msapp.FullName --layout SourceCode --overwrite
if ($LASTEXITCODE -ne 0) { throw '.msapp の組み立てに失敗した。' }

# ---- 5. 詰め直す -----------------------------------------------------------
# Compress-Archive は使わない。ソリューション zip は中身がルート直下に並んでいる
# 必要があり、CreateFromDirectory のほうが確実。
Write-Step 'zip を詰め直す'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  $ext, $zipOut, [System.IO.Compression.CompressionLevel]::Optimal, $false)

if ($NoImport) {
  Write-Step '完了（import はしていない）'
  Write-Host "  $zipOut"
  return
}

# ---- 6. インポート ---------------------------------------------------------
# 直前のソリューション操作が裏で走っていると
# `Cannot start another [Import] because there is a previous [Import] running`
# で弾かれる。少し置いて数回試す。
Write-Step 'インポートして公開'

$ok = $false
for ($i = 1; $i -le 6; $i++) {
  $out = pac solution import --path $zipOut --force-overwrite --publish-changes 2>&1 | Out-String
  if ($out -notmatch 'previous \[Import\] running') {
    Write-Host $out
    if ($LASTEXITCODE -eq 0) { $ok = $true }
    break
  }
  Write-Warn "別のインポートが実行中。40 秒待って再試行する（$i/6）"
  Start-Sleep -Seconds 40
}

if (-not $ok) { throw 'インポートに失敗した。上の出力を確認する。' }

Write-Step '完了。アプリを開き直すと反映されている'
Write-Host "  作業フォルダ: $Work"
