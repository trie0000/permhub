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

.PARAMETER NoPublish
  アプリの公開をしない。Studio で自分で公開するとき。

.PARAMETER NoDataSourceCheck
  データソース名が足りなくても止めない。

.PARAMETER WithApp
  src/App.Formulas.txt と src/App.OnStart.txt もアプリへ反映する。
  既定では中身を突き合わせて、違っていれば知らせるだけ。

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
  [switch]$PruneScreens,
  [switch]$WithApp,
  [switch]$NoDataSourceCheck,
  [switch]$NoPublish
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

# App.OnStart と App.Formulas は画面ではなく App.pa.yaml の中にある。
#     Formulas: |
#       =fMem = ...;
#       ...
#     OnStart: |
#       =Set(...);
# の形なので、画面のようにファイルごと差し替えられない。ブロックの範囲を返す
function Get-AppBlock($lines, $prop) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    # ブロック形式:  OnStart: |
    if ($lines[$i] -match ('^    ' + $prop + ':\s*\|\s*$')) {
      $end = $lines.Count
      for ($j = $i + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j] -match '^    [A-Za-z]') { $end = $j; break }
      }
      $old = @()
      if ($end -gt ($i + 1)) { $old = @($lines[($i + 1)..($end - 1)]) }
      return @{ Start = $i; End = $end; Old = $old }
    }
    # 1 行形式:  OnStart: =Set(x, 1)   （中身が短いとこうなる）
    if ($lines[$i] -match ('^    ' + $prop + ':\s*(=.*)$')) {
      return @{ Start = $i; End = $i + 1; Old = @('      ' + $Matches[1]) }
    }
  }
  return $null
}

# .txt を YAML のブロックスカラーの形にする（6 字下げ、先頭行に =）
function New-AppBlockBody($textPath) {
  $body = @()
  $first = $true
  foreach ($l in @(Get-Content -LiteralPath $textPath -Encoding UTF8)) {
    if ($first) { $body += "      =$l"; $first = $false }
    elseif ($l -eq '') { $body += '' }
    else { $body += "      $l" }
  }
  return $body
}

# App.pa.yaml の 1 プロパティを .txt の中身で入れ替える。
# 返り値の State は same / replaced / added / nowhere
function Set-AppBlock($lines, $prop, $textPath) {
  $body = @(New-AppBlockBody $textPath)
  $blk = Get-AppBlock $lines $prop
  if ($null -ne $blk) {
    if (((@($blk.Old) -join "`n").TrimEnd()) -eq (($body -join "`n").TrimEnd())) {
      return @{ Lines = $lines; State = 'same' }
    }
    $head = @()
    if ($blk.Start -gt 0) { $head = @($lines[0..($blk.Start - 1)]) }
    $tail = @()
    if ($blk.End -lt $lines.Count) { $tail = @($lines[$blk.End..($lines.Count - 1)]) }
    return @{ Lines = @($head + @('    ' + $prop + ': |') + $body + $tail); State = 'replaced' }
  }
  # そもそも入っていないアプリもある。Properties: の直下に足す
  $pi = -1
  for ($k = 0; $k -lt $lines.Count; $k++) {
    if ($lines[$k] -match '^  Properties:\s*$') { $pi = $k; break }
  }
  if ($pi -lt 0) { return @{ Lines = $lines; State = 'nowhere' } }
  $head = @($lines[0..$pi])
  $tail = @()
  if (($pi + 1) -lt $lines.Count) { $tail = @($lines[($pi + 1)..($lines.Count - 1)]) }
  return @{ Lines = @($head + @('    ' + $prop + ': |') + $body + $tail); State = 'added' }
}

function Stop-Here($msg) { Write-Host ''; Write-Host $msg -ForegroundColor Red; exit 1 }

# ---- 0. 前提の確認 ---------------------------------------------------------
Write-Step '前提を確認'

if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
  # Windows / WSL・Linux・macOS で入れ方が違う。pac 本体は .NET のツールなので
  # どれでも動く（このスクリプトも PowerShell 7 があれば OS を問わない）
  if ($IsWindows) {
    $how = @'
    winget install Microsoft.DotNet.SDK.10
    # ここで新しいターミナルを開く（PATH を読み直すため）
    dotnet tool install --global Microsoft.PowerApps.CLI.Tool
    pac auth create --name permhub
'@
  }
  else {
    $how = @'
    # .NET SDK 10 を入れる（Ubuntu / WSL の例）
    sudo apt-get update && sudo apt-get install -y dotnet-sdk-10.0
    dotnet tool install --global Microsoft.PowerApps.CLI.Tool
    export PATH="$PATH:$HOME/.dotnet/tools"     # ~/.bashrc にも書いておく
    pac auth create --name permhub
'@
  }
  Stop-Here @"
pac (Power Platform CLI) が見つからない。入れる。

$how
SDK は 10 が要る。9 以下だと DotnetToolSettings.xml がパッケージで
見つかりませんでした で入らない。

winget の Microsoft.PowerAppsCLI は使わない。中身が powerapps-cli-1.0.msi で
古く、--layout SourceCode が無い。
"@
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
  # zip 内の区切りは / とは限らない。Studio が保存した .msapp は円記号で入っている
  $entries = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -like 'CanvasApps/*.msapp' })
  if ($entries.Count -eq 0) {
    Write-Warn 'このソリューションの中身:'
    foreach ($e in $zip.Entries) { Write-Host "      $($e.FullName)" }
    $zip.Dispose()
    Stop-Here @'
ソリューションにキャンバスアプリが入っていない。

追加したつもりでも入っていないことがある。よくあるのは

  ・保存した直後のアプリは「既存を追加」の一覧に出ない（20 分ほどかかる）
  ・「コード アプリ」など別の種類を選んでいる
    選ぶのは アプリ →「キャンバス アプリ」→「Dataverse の外部」タブ

ポータルでソリューションを開き、中にキャンバスアプリが 1 個あることを
目で確かめてから、もう一度これを流す。
'@
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
  # .msapp のファイル名は接頭辞_英数字だけのスラッグ_id なので、名前が日本語だと
  # 空になって判別できない。customizations.xml の表示名を出す
  $appDisp = ''
  $cx = $zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq 'customizations.xml' }
  if ($cx) {
    $rd = New-Object System.IO.StreamReader($cx.Open(), [System.Text.Encoding]::UTF8)
    try { $xml = $rd.ReadToEnd() } finally { $rd.Dispose() }
    $m = [regex]::Match($xml, '<CanvasApp>.*?<DisplayName>([^<]*)</DisplayName>', 'Singleline')
    if ($m.Success) { $appDisp = $m.Groups[1].Value }
  }
  Write-Host "  対象: $appDisp  [$($entry.Name)]"

  $msappPath = Join-Path $Work 'app.msapp'
  [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $msappPath, $true)

  # データソース名が 1 つでも合っていないと App.OnStart 全体がエラーになり、
  # グローバル変数が一切セットされず、全画面が「名前が認識されません」で埋まる。
  # 症状からは原因が見えないので、ここで突き合わせておく
  Write-Step 'データソースを確認'
  $have = @()
  $app = [System.IO.Compression.ZipFile]::OpenRead($msappPath)
  try {
    $dsEntry = $app.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq 'References/DataSources.json' }
    if ($dsEntry) {
      $rd = New-Object System.IO.StreamReader($dsEntry.Open(), [System.Text.Encoding]::UTF8)
      try { $have = @((($rd.ReadToEnd()) | ConvertFrom-Json).DataSources | ForEach-Object { $_.Name }) }
      finally { $rd.Dispose() }
      # 「ファイルが無い」と「0 件」は原因が違う。区別できるようにしておく
      if ($have.Count -eq 0) { Write-Warn 'References/DataSources.json はあるが 0 件' }
    }
    else {
      Write-Warn 'この .msapp に References/DataSources.json が無い'
      Write-Host "      .msapp の中身: $((($app.Entries | ForEach-Object { $_.FullName }) -join ', '))"
    }
  }
  finally { $app.Dispose() }

  $need = @()
  foreach ($f in @(Get-ChildItem -Path $SrcDir -File |
      Where-Object { $_.Name -like '*.pa.yaml' -or $_.Name -like 'App.*.txt' })) {
    $t = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    # コネクタ名は環境の表示言語になる（Office365ユーザー / Office365Users）。
    # 直後は必ず "." なので、そこまでを名前とみなす
    foreach ($pat in @('PRM_[A-Za-z0-9_]+', 'Office365[^\s.,()]+')) {
      foreach ($m in [regex]::Matches($t, $pat)) { $need += $m.Value }
    }
  }
  $need = @($need | Sort-Object -Unique)
  $missing = @($need | Where-Object { $have -notcontains $_ })

  Write-Host "  アプリ側: $(($have | Sort-Object) -join ', ')"
  if ($missing.Count -gt 0) {
    Write-Warn 'src が使っているのにアプリに無い名前:'
    foreach ($m in $missing) { Write-Host "      $m" -ForegroundColor Yellow }
    if (-not $NoDataSourceCheck) {
      $zip.Dispose()
      Stop-Here @'
このまま入れると壊れたアプリになるので止めた。

■ 追加したのに 10 個とも出るなら、まず「公開」していない
  solution export が取ってくるのは公開済みのバージョン。保存だけでは反映されない。
  アプリを開いて 右上「公開」→「このバージョンを公開する」→ タブを閉じる
  → もう一度これを流す。

■ それでも変わらないなら、触っているアプリが違う
  上の「対象:」に出た表示名が、自分が編集したアプリと同じか確かめる。

データソースはリストの GUID とサイト URL に紐づいているので、YAML では作れない。
アプリを開いて、その環境の SharePoint サイトに対して自分で追加するしかない。

  左の「データ」→「データの追加」→ SharePoint → サイトを選ぶ
  → 上に出た名前のリストにチェック → 接続

コネクタ（Office365... ）は同じ画面の検索から追加する。名前は環境の表示言語に
なるので、日本語環境なら Office365ユーザー / Office365グループ。

追加したら保存して、タブを閉じてから、もう一度このスクリプトを流す。

止めずに進めるなら -NoDataSourceCheck。
'@
    }
  }
  else { Write-Host '  src が使う名前はすべて揃っている' }

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

  # App.Formulas / App.OnStart は App.pa.yaml の中なので、画面と同じようには入らない。
  # 黙って上書きするとテナント側で直したコネクタ名などを消してしまうので、
  # 既定は突き合わせて知らせるだけにする
  $appYaml = Join-Path $srcIn 'App.pa.yaml'
  $appLines = @(Get-Content -LiteralPath $appYaml -Encoding UTF8)
  $appChanged = $false
  foreach ($pair in @(@('Formulas', 'App.Formulas.txt'), @('OnStart', 'App.OnStart.txt'))) {
    $prop = $pair[0]
    $txt = Join-Path $SrcDir $pair[1]
    if (-not (Test-Path $txt)) { continue }
    $r = Set-AppBlock $appLines $prop $txt
    if ($r.State -eq 'same') { Write-Host "  App.$prop は一致" }
    elseif ($r.State -eq 'nowhere') { Write-Warn "App.pa.yaml に Properties: が見つからない" }
    elseif ($WithApp) {
      $appLines = @($r.Lines)
      $appChanged = $true
      if ($r.State -eq 'added') { Write-Host "  App.$prop を新しく入れた" }
      else { Write-Host "  App.$prop を差し替え" }
    }
    elseif ($r.State -eq 'added') { Write-Warn "App.$prop がアプリに無い。入れるなら -WithApp" }
    else { Write-Warn "App.$prop がアプリ側と違う。反映するなら -WithApp" }
  }
  # 画面を消したときに StartScreen がその画面を指したままだとアプリが開けない。
  # 新規の空アプリに流し込むと必ずこれになる（Screen1 を消すため）
  $present = @(Get-ChildItem -Path $srcIn -Filter '*.pa.yaml' -File |
    Where-Object { $_.Name -ne 'App.pa.yaml' -and $_.Name -notlike '_*' } |
    ForEach-Object { $_.Name -replace '\.pa\.yaml$', '' })
  for ($k = 0; $k -lt $appLines.Count; $k++) {
    if ($appLines[$k] -match '^    StartScreen:\s*=\s*(.+?)\s*$') {
      $cur = $Matches[1]
      if ($present -notcontains $cur) {
        $appLines[$k] = '    StartScreen: =' + $Screens[0]
        $appChanged = $true
        Write-Warn "StartScreen が $cur を指していたが、その画面は無い。$($Screens[0]) にした"
      }
      break
    }
  }

  if ($appChanged) {
    Set-Content -LiteralPath $appYaml -Value $appLines -Encoding UTF8
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

# ---- 6. アプリを公開 -------------------------------------------------------
# ソリューションの取り込みではキャンバスアプリは公開されない。取り込みで変わるのは
# 「保存された版」で、利用者に配られる「公開された版」は別。実機で確かめた:
# 取り込み直後のプレイヤーは古い中身のまま「新しいバージョンを間もなく利用できます」
# と出し、Studio で公開して初めて切り替わる。
#
# Publish-AdminPowerApp は .NET Framework 製で PowerShell 7 では動かないため、
# Windows PowerShell 5.1 を別に呼ぶ。無ければ手で公開してもらう。
if (-not $NoPublish) {
  Write-Step 'アプリを公開'
  $ps5 = $null
  foreach ($c in @('powershell.exe', '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe')) {
    $g = Get-Command $c -ErrorAction SilentlyContinue
    if ($g) { $ps5 = $g.Source; break }
  }
  if (-not $ps5) {
    Write-Warn 'Windows PowerShell 5.1 が無いので公開できない。'
    Write-Warn 'Studio でアプリを開いて「公開」→「このバージョンを公開する」。'
  }
  else {
    # 単一引用符の中では $ が展開されないので、逃がし文字が要らない
    $q = $appDisp.Replace("'", "''")
    $inner = 'Import-Module Microsoft.PowerApps.Administration.PowerShell; ' +
             '$a = @(Get-AdminPowerApp | Where-Object { $_.DisplayName -eq ''' + $q + ''' }); ' +
             'if ($a.Count -eq 0) { throw ''その表示名のアプリが見つからない'' }; ' +
             'if ($a.Count -gt 1) { throw ''同じ表示名のアプリが複数ある'' }; ' +
             'Publish-AdminPowerApp -EnvironmentName $a[0].EnvironmentName -AppName $a[0].AppName; ' +
             'Write-Output ''published'''
    $out = & $ps5 -NoProfile -ExecutionPolicy Bypass -Command $inner 2>&1
    if (($out -join [Environment]::NewLine) -match 'published') {
      Write-Host "  公開した: $appDisp"
    }
    else {
      foreach ($l in $out) { Write-Host "      $l" }
      Write-Warn '公開できなかった。初回は次の 2 つが要る（Windows PowerShell 5.1 で実行）。'
      Write-Warn '  Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser'
      Write-Warn '  Add-PowerAppsAccount      # サインイン。8 時間ほど保つ'
      Write-Warn 'それでも駄目なら Studio で「公開」を押す。'
    }
  }
}

Write-Step '完了。アプリを開き直すと反映されている'
Write-Host "  作業フォルダ: $Work"
