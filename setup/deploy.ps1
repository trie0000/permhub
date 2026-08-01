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

.PARAMETER PruneScreens
  src に無い画面をアプリから削除する。名前がぶつかって取り込めないときに使う。

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
  [switch]$NoImport,
  [switch]$PruneScreens
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
if (-not $SrcDir) { $SrcDir = Join-Path $Root 'src' }

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
# 利用者が直せる失敗はこれで止める。throw だと本文が 2 回出て読みにくい
# .pa.yaml のコントロール定義は
#     - drpOrg1:
#         Control: ModernDropdown@1.0.2
# の形。次の行が Control: のものだけ拾えば、数式の中の "- xxx:" を拾わずに済む
function Get-ControlNames($path) {
  $names = @()
  $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*-\s+([A-Za-z_][A-Za-z0-9_]*):\s*$') {
      $n = $Matches[1]
      if (($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s*Control:\s') { $names += $n }
    }
  }
  return $names
}

function Stop-Here($msg) { Write-Host ''; Write-Host $msg -ForegroundColor Red; exit 1 }

# ---- 0. 前提の確認 ---------------------------------------------------------
Write-Step '前提を確認'

if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
  Stop-Here @'
pac (Power Platform CLI) が見つからない。コマンドで入る。

    winget install Microsoft.DotNet.SDK.10
    # ここで新しいターミナルを開く（PATH を読み直すため）
    dotnet tool install --global Microsoft.PowerApps.CLI.Tool
    pac auth create --name permhub

**SDK は 10 でないと駄目。** pac は NuGet に出ている全バージョンが net10.0 専用で、
SDK 9 以下だと次で失敗する:

    設定ファイル 'DotnetToolSettings.xml' がパッケージで見つかりませんでした

ランタイムだけだと "No .NET SDKs were found" になる。SDK が要る。

winget の Microsoft.PowerAppsCLI は使わない。中身が powerapps-cli-1.0.msi で
古く、このスクリプトが使う --layout SourceCode が無い。
'@
}

# pac が古いと --layout SourceCode が無く、このスクリプトは動かない。
# バージョン番号ではなくヘルプに SourceCode があるかで判定する（版によって番号体系が違うため）
$packHelp = pac canvas pack 2>&1 | Out-String
if ($packHelp -notmatch 'SourceCode') {
  Stop-Here @'
pac が古い。`pac canvas pack` に --layout SourceCode が無い。

    pac --version

で版を確認し、新しいものを入れ直す:

    dotnet tool update --global Microsoft.PowerApps.CLI.Tool
'@
}

$auth = pac auth list 2>&1 | Out-String
if ($auth -match 'No profiles were found') {
  Stop-Here '認証プロファイルが無い。pac auth create --name permhub を実行する。'
}

# どのテナント・どの環境に流すのかを先に出す。プロファイルを複数持っていると
# 意図しないテナントのアプリを上書きしかねない
Write-Step '接続先'
pac auth who

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
  Stop-Here "重複 $dupTotal 件。このまま取り込むと PA1001 で失敗する。直してから再実行する。"
}
Write-Host '  重複なし'

# ---- 2. 作業フォルダ -------------------------------------------------------
$Work = Join-Path ([System.IO.Path]::GetTempPath()) "permhub-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $Work -Force | Out-Null
$zipIn = Join-Path $Work 'sol.zip'
$zipOut = Join-Path $Work 'sol-mod.zip'

# ---- 3. エクスポート -------------------------------------------------------
Write-Step "ソリューション '$SolutionName' をエクスポート"
pac solution export --path $zipIn --name $SolutionName --overwrite
if ($LASTEXITCODE -ne 0) {
  Write-Warn "ソリューション '$SolutionName' が無い。この環境にある一意名:"
  # 表のまま出すと表示名（日本語）で折り返して読めないので、1 列目だけ並べる
  $names = @()
  foreach ($l in (pac solution list 2>&1)) {
    if ($l -match '^([A-Za-z_][A-Za-z0-9_]*)\s{2,}') { $names += $Matches[1] }
  }
  foreach ($n in $names) { Write-Host "      $n" }
  if ($names.Count -eq 0) { Write-Host '      （1 つも無い）' }
  Stop-Here @'
次のどれか。

[1] 一意名の取り違え
    上に並んだ名前（表示名ではない）を -SolutionName に渡す。

[2] このテナントではまだ準備していない
    上に目的の名前が無いならこれ。そのテナントで
    アプリを作る（docs/deploy.md 手順 1〜6）→ ソリューションに入れる（手順 9）
    を先にやる。ソリューションは export/import でテナント間を運べない。

[3] 接続先が違う
    上の「接続先」の表示を見る。違うなら
        pac auth list
        pac auth select --index <番号>
'@
}

# ---- 4. zip の中の .msapp だけを差し替える ---------------------------------
# 解凍して詰め直してはいけない。Windows PowerShell 5.1 は .NET Framework で動き、
# そこの ZipFile.CreateFromDirectory は zip 内のパス区切りに OS の区切り文字を使う。
# つまり Windows では
#     CanvasApps\..._DocumentUri.msapp     ← 円記号
# というエントリ名になる。zip の仕様も customizations.xml の参照も / なので、
# 取り込み側はアプリ本体を見つけられず
#     CanvasApp import: FAILURE:
#     The solution specified an expected assets file but that file was missing or invalid
# で落ちる。macOS/Linux の PowerShell 7 は / なので同じスクリプトでも通ってしまい、
# 手元では再現しない。加えて Expand-Archive は
#     [Content_Types].xml      … 名前に [ ] を含む（PowerShell ではワイルドカード）
#     *_BackgroundImageUri     … 拡張子が無い
# の扱いも怪しい。
#
# そこで解凍せず、zip を開いたまま .msapp のエントリだけ入れ替える。エントリ名は
# 元のものをそのまま使い回すので区切り文字は変わらず、他のファイルには一切触らない。
Add-Type -AssemblyName System.IO.Compression.FileSystem
Copy-Item $zipIn $zipOut -Force

$zip = [System.IO.Compression.ZipFile]::Open($zipOut, [System.IO.Compression.ZipArchiveMode]::Update)
try {
  $entries = @($zip.Entries | Where-Object { $_.FullName -like 'CanvasApps/*.msapp' })
  if ($entries.Count -eq 0) {
    $zip.Dispose()
    Stop-Here 'ソリューションにキャンバスアプリが入っていない。docs/deploy.md 手順 9-2 を先にやる。'
  }
  if ($entries.Count -gt 1) {
    # 取り違えると別のアプリを壊すので、黙って 1 つ目を選ばない
    Write-Warn 'このソリューションにキャンバスアプリが複数ある:'
    foreach ($e in $entries) { Write-Host "      $($e.Name)" }
    $zip.Dispose()
    Stop-Here 'どれに反映するか決められない。ソリューションはアプリ 1 つにする。'
  }
  $entry = $entries[0]
  $entryName = $entry.FullName
  Write-Host "  対象: $($entry.Name)"

  $msappPath = Join-Path $Work 'app.msapp'
  [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $msappPath, $true)

  Write-Step '画面を差し替え'
  $srcOut = Join-Path $Work 'unpacked'
  pac canvas unpack --msapp $msappPath --sources $srcOut --layout SourceCode
  if ($LASTEXITCODE -ne 0) { $zip.Dispose(); Stop-Here '.msapp の展開に失敗した。' }

  # コントロール名はアプリ全体で一意。src に無い画面が残っていて、そこに同じ名前の
  # コントロールがあると取り込みが
  #     error PA2110 : An entity with name 'xxx' already exists
  # で落ちる。黙って消すと相手の作った画面を壊すので、ぶつかったときだけ止める
  $srcIn = Join-Path $srcOut 'Src'
  $others = @(Get-ChildItem -Path $srcIn -Filter '*.pa.yaml' -File |
    Where-Object { $_.Name -ne 'App.pa.yaml' -and $_.Name -notlike '_*' } |
    ForEach-Object { $_.Name -replace '\.pa\.yaml$', '' } |
    Where-Object { $Screens -notcontains $_ })

  if ($others.Count -gt 0) {
    Write-Warn "アプリ側に src に無い画面がある: $($others -join ', ')"
    if ($PruneScreens) {
      foreach ($o in $others) {
        Remove-Item (Join-Path $srcIn "$o.pa.yaml") -Force
        Write-Host "  削除: $o"
      }
    }
    else {
      $mine = @{}
      foreach ($s in $Screens) {
        foreach ($n in (Get-ControlNames (Join-Path $SrcDir "$s.pa.yaml"))) { $mine[$n] = $s }
      }
      $clash = @()
      foreach ($o in $others) {
        foreach ($n in (Get-ControlNames (Join-Path $srcIn "$o.pa.yaml"))) {
          if ($mine.ContainsKey($n)) { $clash += "$n  ($o と $($mine[$n]))" }
        }
      }
      if ($clash.Count -gt 0) {
        Write-Warn 'コントロール名がぶつかっている:'
        foreach ($c in $clash) { Write-Host "      $c" }
        $zip.Dispose()
        Stop-Here @'
コントロール名はアプリ全体で一意なので、このまま入れると取り込みが
    error PA2110 : An entity with name 'xxx' already exists
で落ちる。どちらかにする。

[1] その画面が要らないなら消す
        .\setup\deploy.ps1 -SolutionName <一意名> -PruneScreens
    src に無い画面をアプリから削除したうえで反映する。
    アプリからその画面が消えるので、中身が要らないことを確かめてから。

[2] その画面を残したいなら
    Studio でその画面のコントロールを、上に出た名前と重ならない名前に変える。
'@
      }
      Write-Host '  名前の衝突は無いのでそのまま残す'
    }
  }

  foreach ($s in $Screens) {
    $from = Join-Path $SrcDir "$s.pa.yaml"
    $to = Join-Path (Join-Path $srcOut 'Src') "$s.pa.yaml"
    if (-not (Test-Path $to)) { Write-Warn "$s はアプリ側に無い。新しい画面として入る" }
    Copy-Item $from $to -Force
    Write-Host "  $s.pa.yaml"
  }

  pac canvas pack --sources $srcOut --msapp $msappPath --layout SourceCode --overwrite
  if ($LASTEXITCODE -ne 0) { $zip.Dispose(); Stop-Here '.msapp の組み立てに失敗した。' }

  Write-Step 'zip の .msapp を差し替え'
  $entry.Delete()
  $newEntry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
  $out = $newEntry.Open()
  try {
    $bytes = [System.IO.File]::ReadAllBytes($msappPath)
    $out.Write($bytes, 0, $bytes.Length)
  } finally { $out.Dispose() }
}
finally { $zip.Dispose() }

# 差し替え以外のファイルが失われていないか確かめる。落ちていると取り込みが
# assets file missing で失敗するので、ここで気づけるようにする
$before = [System.IO.Compression.ZipFile]::OpenRead($zipIn)
$after = [System.IO.Compression.ZipFile]::OpenRead($zipOut)
try {
  $b = @($before.Entries | ForEach-Object { $_.FullName })
  $a = @($after.Entries | ForEach-Object { $_.FullName })
  $lost = @($b | Where-Object { $a -notcontains $_ })
  if ($lost.Count -gt 0) {
    Write-Warn '詰め直しでファイルが落ちた:'
    foreach ($l in $lost) { Write-Host "      $l" }
  } else {
    Write-Host "  同梱ファイル $($a.Count) 件（欠落なし）"
  }
} finally { $before.Dispose(); $after.Dispose() }

if ($NoImport) {
  Write-Step '完了（import はしていない）'
  Write-Host "  $zipOut"
  return
}

# ---- 5. インポート ---------------------------------------------------------
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
