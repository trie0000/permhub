# Power Platform CLI での取り回し（検証済み）

画面ごとにツリービューへ貼り付ける作業を減らすため、`pac`（Power Platform CLI）で
`.msapp` と YAML を往復できるか検証した結果。

**結論: 取り出し（アプリ → YAML）と組み立て（YAML → `.msapp`）は自動化できる。
`.msapp` をテナントへ戻す部分だけ手作業が残る。**

## 分かったこと

| | 結果 |
|---|---|
| `pac canvas unpack --layout SourceCode` の出力形式 | **`src/` の `.pa.yaml` と同じ**。変換不要 |
| unpack → pack → unpack の往復 | **完全一致**（`diff -rq` で差分なし） |
| `src/*.pa.yaml` を差し込んで pack | **成功** |
| `pac canvas download` が取るもの | **公開済みバージョンのみ。** 保存しただけの変更は落ちてこない |
| `.msapp` をテナントへ戻すコマンド | **無い**（`pac canvas` に upload/import は無い） |

## セットアップ

```bash
dotnet tool install --global Microsoft.PowerApps.CLI.Tool
export PATH="$PATH:$HOME/.dotnet/tools"
```

> **`dotnet tool install` は .NET SDK が要る。** ランタイムだけの PC では
> `No .NET SDKs were found` で失敗する。Windows ならコマンドで入る。
>
> ```powershell
> winget install Microsoft.DotNet.SDK.10
> # 新しいターミナルを開いてから
> dotnet tool install --global Microsoft.PowerApps.CLI.Tool
> ```
>
> **SDK は 10 が要る。** pac は NuGet 上の全バージョンが `net10.0` 専用で、
> SDK 9 以下だと `DotnetToolSettings.xml がパッケージで見つかりませんでした`
> で入らない。古い pac を `--version` で指定しても回避できない。
>
> **`winget install Microsoft.PowerAppsCLI` は使わない。** 中身が
> `powerapps-cli-1.0.msi` で古く、`--layout SourceCode` が無い。

Homebrew の dotnet を使っている場合、`pac` が .NET ランタイムを見つけられない。
`DOTNET_ROOT` を指す。

```bash
export DOTNET_ROOT="/opt/homebrew/opt/dotnet/libexec"
```

認証（ブラウザでサインイン画面が出る）。

```bash
pac auth create --name permhub
```

`--name` は手元のラベル。好きに付けてよく、テナント名とは無関係。複数テナントを
使い分けるときに `pac auth list` / `pac auth select` で切り替えるためのもの。
**`pac auth who` で今の行き先を確かめてから流すこと。**

## 取り出す（アプリ → YAML）

**先に Studio で「公開」する。** `pac canvas download` は公開済みバージョンしか返さないので、
保存しただけだと古い内容が落ちてくる。

```bash
pac canvas list                                  # アプリ名と App ID を確認
pac canvas download --name <App ID> --file-name cur.msapp --overwrite
pac canvas unpack --msapp cur.msapp --sources out --layout SourceCode
# out/Src/*.pa.yaml が src/ と同じ形式
```

> 同名のアプリが複数あると `--name` は「Multiple canvas apps matching name」で失敗する。
> App ID（Studio の URL の `app-id=` の GUID）を渡す。

## 組み立てる（YAML → `.msapp`）

```bash
pac canvas pack --sources out --msapp new.msapp --layout SourceCode --overwrite
```

`out/Src/ScrHome.pa.yaml` などを差し替えてから pack すれば、画面の内容が入れ替わった
`.msapp` ができる。

> pack は「Studio で一度開いて検証しろ」と警告を出す。YAML から組み立てた `.msapp` は
> Studio で開くまで検証されていない、という意味。

## 組み立てる前に検査する

**`pac canvas pack` は壊れた YAML を素通しする。** パックは成功して、取り込みで
初めて `PA1001 ... Duplicate name 'Fill'` のように落ちる。`pac canvas validate` は廃止済み。
Python の `yaml.safe_load` も既定では重複キーを許す（後勝ち）ので気づけない。

そこで自前で見る。

```bash
python3 setup/check-yaml.py
```

同じ `Properties` ブロックに同名のプロパティが 2 つあると、行番号を出して exit 1 になる。
**そのコントロールに無いプロパティ**と、**括弧が合っていない式**も落とす。

```
src/ScrUser.pa.yaml:217: ModernText に 'Placeholder' は無い（txtName）
```

これは**取り込みは通るのに Studio で開くと落ちる**種類の間違い。

```
error PA2108 : Unknown property 'Placeholder' for control type 'ModernText@1.0.0'
```

入力欄（`ModernTextInput`）を文字（`ModernText`）に変えたときの消し忘れで踏んだ。

括弧のほうはこう出る。

```
src/ScrHome.pa.yaml:1013: Fill の括弧が合わない（閉じ括弧が多い 1）
```

**式の一部を機械的に消すと、閉じ括弧だけ残る。** `If(cond, a, <式>)` の `If(cond, a, `
だけを消すと `<式>)` になり、取り込みは通るのに Studio で
`予期しない文字があります` になる。組織区分1 の要否を外したときに 9 箇所踏んだ。
プロパティ名は [Text modern control](https://learn.microsoft.com/en-us/power-apps/maker/canvas-apps/controls/modern-controls/modern-control-text) に合わせてある。

> プロパティの値が複数行のクォート形式で書かれていることがある。
>
> ```yaml
>           Fill: '=RGBA(250, 250, 247, 1)
>
>             '
> ```
>
> `Fill: =` を探す検査だとこれを見落とし、「Fill が無い」と誤判定して二重に足してしまう。
> **キー名だけで突き合わせること。**

## `ItemDisplayText` には式を置けない

ドロップダウンの `ItemDisplayText` は**列の参照しか受け付けない**。関数も名前付き数式も
置けず、Studio の「アプリのチェック」で落ちる。

```
このプロパティの式では fChgByO1 を使用できません
この関数 LookUp はこのプロパティでは使用できません
この関数 Coalesce はこのプロパティでは使用できません
```

**表示用の文字は `Items` の側で作る。**

```yaml
Items: =fMyOrg1D                 # ForAll(...) で Disp 列を作った名前付き数式
ItemDisplayText: =ThisItem.Disp  # 列の参照だけ
```

編集中の状態に追随させたいなら、`Items` を名前付き数式（または ForAll 式）にする。
`ClearCollect` でコレクションに入れてしまうと、その時点の値で固まる。

> **`Filter(col, true)` は警告になる。**「この述語はリテラル値である」。
> 絞り込まないならコレクションをそのまま渡す。

## コネクタの戻り値の名前（実地で踏んだところ）

**`Office365ユーザー` は関数によって列名の綴りが違う。**

| 関数 | 戻り | 列名 |
|---|---|---|
| `MyProfileV2()` / `UserProfileV2(id)` | `GraphUser_V1` | **camelCase**（`id` `displayName` `department` `mail`） |
| `SearchUserV2({searchTerm, top}).value` | `array of User` | **PascalCase**（`Id` `DisplayName` `Department` `Mail` `UserPrincipalName`） |

同じコネクタでも V2 の「プロファイル系」は Graph の綴り、「検索」は旧来の綴りになる。
`SearchUserV2().value` を camelCase で読んで `名前が無効です。'mail' は認識されません`
で落ちた。`SearchUser`（V1）は非推奨なので使わない。

出典: [Office 365 Users コネクタ](https://learn.microsoft.com/en-us/connectors/office365users/)

## 戻す（`.msapp` → テナント）— ここだけ手作業

`pac canvas` にアップロードコマンドは無い。UI から入れる。

**アプリ一覧 →「アプリをインポートする」→「ファイルから (.msapp)」**（実在を確認済み）。
`.zip`（パッケージ）と `.msapp` の 2 つが選べる。

Studio の「…」メニューには「アプリのバージョン履歴」しか無く、**Studio 側から
ローカルの `.msapp` を開く導線は無い**。取り込みはアプリ一覧から行う。

| | 貼り付け方式 | `.msapp` 取り込み | ソリューション経由 |
|---|---|---|---|
| 操作 | コピー → 画面削除 → 貼り付け ×3 画面 | ファイルを 1 つ選ぶ | **コマンドのみ** |
| 操作数 | 12〜15 | 3 | 0 |
| 結果 | 既存アプリを更新 | **新規アプリになる** | **既存アプリを更新** |
| 向く用途 | — | 別テナントへの初回導入 | **反復開発** |

> **未確認**: 取り込みが既存アプリの更新になるのか、新規アプリとして作られるのかは
> 未検証（ブラウザ自動化からローカルファイルを上げられなかったため）。
> 新規アプリになる場合、反復開発には向かず、別テナントへの初回導入向けになる。

## ソリューション経路で既存アプリを更新する（検証済み）

**YAML を直してコマンドだけで既存アプリを更新できる。** 貼り付けも `.msapp` の取り込みも要らない。

### 前提

- **Premium は不要。Entra ID のアプリ登録・サービスプリンシパルも不要。**
  `pac auth create` の対話ログイン（`Type: User`）で足りる。
  アプリ登録が要るのは GitHub Actions などで無人実行するときだけ
- Dataverse のある環境
- アプリがソリューションに入っていること（下の初回準備）

### 初回だけの準備

1. ポータルの **ソリューション →「新しいソリューション」**。
   **公開元はどれでもよい**（決めるのは接頭辞だけ。`deploy.ps1` は `*.msapp` で拾う）
2. **「既存を追加」→「アプリ」→「キャンバス アプリ」→「Dataverse の外部」**タブ
   → アプリを選んで「追加」

ここで 2 つ引っかかる。

- **保存した直後のアプリは一覧に出ない。** 検索しても出てこない。
  インデックスの反映待ちで、**20 分ほどで出る**
- **そのアプリを Studio で開いていると追加できない。**
  `'<アプリ名>' is locked by user ... please wait at least 15 minutes` と出る。
  タブを閉じる（別ページへ移動する）と**すぐ**解放される。メッセージの 15 分は
  ブラウザが落ちるなどして解放を伝えられなかったときの上限で、正常に閉じたなら待たなくてよい

### WSL / Linux / macOS でも同じスクリプトで動く

`deploy.ps1` は **PowerShell 7 があれば OS を問わない**。`pac` は .NET のツールなので
Windows 専用ではない。WSL から流しても同じ結果になる。

```bash
# .NET SDK 10（Ubuntu / WSL）
sudo apt-get update && sudo apt-get install -y dotnet-sdk-10.0 powershell
dotnet tool install --global Microsoft.PowerApps.CLI.Tool
export PATH="$PATH:$HOME/.dotnet/tools"     # ~/.bashrc にも書いておく
pac auth create --name permhub
```

```bash
pwsh ./setup/deploy.ps1 -SolutionName <一意名>
```

OS 依存の分岐はスクリプトに 1 箇所だけある。`pac` が入っていないときの案内文で、
`$IsWindows` を見て winget と apt を出し分けている。処理そのものは共通。

**Windows PowerShell 5.1 でだけ効く作りにはしていない。** zip はエントリを名前で
差し替えるので、パス区切りが `/` でも円記号でも壊れない（→ 下の「解凍して詰め直さない」）。

> `pac auth create` はブラウザを開く。WSL でブラウザが開かないときは、
> 端末に出るデバイスコードの URL を Windows 側のブラウザに貼る。

### 毎回の更新（Windows / PowerShell）

[setup/deploy.ps1](../setup/deploy.ps1) を叩くだけ。

```powershell
.\setup\deploy.ps1 -SolutionName permhub
```

実行の最初に**どのアプリを触るのかを表示名で出す**。

```
対象: 権限申請  [cr875_permhubsolutiontest_09c62_DocumentUri.msapp]
```

`.msapp` のファイル名は「接頭辞_英数字だけのスラッグ_id」なので、**アプリ名が日本語だと
スラッグが空になり `crdca__52819` のようになって判別できない**。表示名を見て、
**自分が編集しているアプリと同じか確かめること。** 違っていたら、ソリューションに
入っているのが別のアプリ。

やっていること: YAML の重複検査 → `pac solution export` → **zip の中の `.msapp` だけを
その場で差し替え**（`unpack` → `src/*.pa.yaml` で画面を差し替え → `pack`）→
`pac solution import --publish-changes`。

| オプション | |
|---|---|
| `-Screens ScrHome` | 差し替える画面を絞る（既定は ScrHome / ScrUser / ScrReq） |
| `-WithApp` | `App.Formulas` と `App.OnStart` も反映する（下記） |
| `-PruneScreens` | `src` に無い画面をアプリから削除する（下記） |
| `-NoImport` | zip を作るところで止める。中身を見たいとき |
| `-SrcDir <path>` | 差し替え元を変える（既定は `src`） |

### データソース名の突き合わせ

`deploy.ps1` は毎回、**アプリが持っているデータソース名**（`.msapp` の
`References/DataSources.json`）と、**`src` が使っている名前**を突き合わせる。

```
==> データソースを確認
  アプリ側: Office365グループ, Office365ユーザー, PRM_Config, PRM_Grants, ...
  ! src が使っているのにアプリに無い名前:
      PRM_Users
```

**名前が 1 つでも合っていないと `App.OnStart` 全体がエラーになる。** そうなると
`gblIsAdmin` などのグローバル変数が一切セットされず、それを参照している全画面が
「名前が認識されません」で埋まる。**症状（大量の名前エラー）からは原因が見えない**ので、
ここで先に出す。

データソース名は**追加した時点のリスト名**になる。後からリストを改名しても
アプリ側の名前は変わらない。

### 取り込んだだけでは公開されない

**`pac solution import --publish-changes` はキャンバスアプリを公開しない。**
取り込みで変わるのは「保存された版」で、**利用者に配られる「公開された版」は別**。

実機で確かめた。取り込み直後のプレイヤーは古い中身のまま

```
このアプリの新しいバージョンを間もなく利用できます。公開されたらお知らせします。
```

と出し、Studio で公開して初めて

```
このアプリの古いバージョンを使用しています。更新して、最新バージョンを使用してください。
```

に変わる。**毎回必要**で、1 回だけではない。

`deploy.ps1` は取り込みのあとに公開まで行う。`Publish-PowerApp` は
**.NET Framework 製で PowerShell 7 では動かない**ので、Windows PowerShell 5.1 を
別に呼んでいる。5.1 が無い環境（WSL / Linux / macOS）では飛ばして、
Studio で公開するよう促す。

初回だけ、**Windows PowerShell 5.1 で**この 2 つが要る。

```powershell
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
Install-Module Microsoft.PowerApps.PowerShell -Scope CurrentUser -AllowClobber
```

> **公開のコマンドレットは `Publish-PowerApp`。** Administration 側ではなく
> `Microsoft.PowerApps.PowerShell`（メーカー向け）にある。`Publish-AdminPowerApp`
> という名前は**存在しない**。無い名前を呼んでも `;` で繋いだ後続は動くので、
> 成否の判定を甘くすると失敗を成功と誤認する。`$ErrorActionPreference = 'Stop'` を置く。

```powershell
Add-PowerAppsAccount
```

サインインは 8 時間ほど保つ。`pac auth` とは別系統なので、両方が要る。

> `Install-Module` が `ShouldContinue` の例外で落ちるときは、NuGet プロバイダの
> 導入で対話プロンプトが出せていない。先に入れておく。
>
> ```powershell
> Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
> ```

`-NoPublish` で公開だけ飛ばせる。

#### 無人で公開する（サービスプリンシパル）

このモジュールの認証は**セッション（プロセス）の中**に持たれる。別プロセスで叩くと
引き継がれないので、`deploy.ps1` は公開の直前に同じプロセスでサインインする。
それでも対話サインインは切れるので、無人で回すならサービスプリンシパルにする。

**テナント管理者の権限が要る。** 手順は 3 つ。

1. Entra ID で**アプリ登録**を作り、**クライアントシークレット**を発行する
2. そのアプリを Power Platform の管理アプリとして登録する（Windows PowerShell 5.1）

   ```powershell
   New-PowerAppManagementApp -ApplicationId <アプリID>
   ```

3. 環境変数を 3 つ渡す

   ```powershell
   $env:PERMHUB_SP_TENANT = "<テナントID>"
   $env:PERMHUB_SP_APPID  = "<アプリID>"
   $env:PERMHUB_SP_SECRET = "<シークレット>"
   ```

3 つそろっていれば無人でサインインし、そろっていなければ対話サインインに戻る。

> **WSL から Windows の `powershell.exe` を呼ぶ場合は `WSLENV` に並べる。**
> 並べないと環境変数が渡らず、値が空のまま**対話サインインに落ちる**。
> 承認画面が出るのに「無人で動いている」と誤認しやすい。
>
> ```bash
> export WSLENV="PERMHUB_SP_TENANT:PERMHUB_SP_APPID:PERMHUB_SP_SECRET"
> ```
>
> `deploy.ps1` は Linux / macOS 上で動いているときに自分で設定する。

> **シークレットはリポジトリにも env ファイルにも置かない。** 環境変数で渡す。
> `deploy.ps1` はシークレットをコマンドラインに載せず、子プロセスが環境変数から
> 読む形にしてある（プロセス一覧に出さないため）。
>
> シークレットには**有効期限**がある（既定 6〜24 か月）。切れたら作り直す。

**人が叩く運用なら要らない。** 初回にダイアログが 1 回出るだけで、しばらく保つ。

### `App.Formulas` と `App.OnStart`

**この 2 つは画面ファイルではなく `App.pa.yaml` の中にある。**

```yaml
App:
  Properties:
    Formulas: |
      =fMem = Filter(colMemberAll, Org1Code = gblOrg1);
      ...
    OnStart: |
      =Set(gblMyAdId, Office365ユーザー.MyProfileV2().id); ...
    StartScreen: =ScrHome
```

画面のようにファイルごと差し替えられないので、`deploy.ps1` は**このブロックの中身だけ**を
`src/App.Formulas.txt` / `src/App.OnStart.txt` で入れ替える。`StartScreen` や `Theme` は触らない。

`OnStart:` が 1 行で書かれている（中身が短いとこうなる）アプリでも拾う。
**そもそも入っていないアプリなら `-WithApp` で新しく入れる**（`Properties:` の直下）。

既定は**突き合わせて知らせるだけ**。テナント側でコネクタ名などを直していると、
黙って上書きすると消えてしまうため。

```
! App.Formulas がアプリ側と違う（80 行 → 81 行）。反映するなら -WithApp
```

反映するなら `-WithApp` を付ける。

```powershell
.\setup\deploy.ps1 -SolutionName <一意名> -WithApp
```

**`OnStart` を入れ替えても自動では走らない。** アプリを開いて
`App` の `…` →「OnStart を実行します」を押す（プレビューでも再実行されない）。

> **`OnStart` にエラーが 1 つでもあると、黙って何も実行されない。**
> 画面は出るのにデータが空、という見え方になる。聴診器アイコンの
> 「アプリのチェック」→「数式」でエラーを 0 にする。別テナントで多いのは
> コネクタ名の言語違い（`Office365ユーザー` ↔ `Office365Users`）と
> データソースの繋ぎ忘れ。

### `src` に無い画面が残っているとき

**コントロール名はアプリ全体で一意。** そのテナントのアプリに `src` に無い画面が
残っていて、そこに同じ名前のコントロールがあると、取り込みが落ちる。

```
Src\ScrHome.pa.yaml(70,7) : error PA2110 : An entity with name 'drpOrg1'
already exists. Other definition located at Src\ScrEdit.pa.yaml(194,9).
```

`deploy.ps1` は展開した時点で `src` に無い画面を見つけ、**コントロール名がぶつかって
いるものだけを並べて止める**。ぶつかっていなければそのまま残して続ける。

その画面が要らないなら消してから反映する。**アプリからその画面が消える**ので、
中身が要らないことを確かめてから。

```powershell
.\setup\deploy.ps1 -SolutionName <一意名> -PruneScreens
```

残したいなら、Studio でその画面のコントロールを重ならない名前に変える。

> 画面を消して `pac canvas pack` しても通ることは確認済み。`_EditorState.pa.yaml` が
> その画面を参照したままでも pack が畳んでくれる。

**`-SolutionName` に渡すのは「一意名」**（表示名ではない）。`pac solution list` の
`Unique Name` 列。違う名前を渡すと

```
Error: The given solution unique name (xxx) is not valid
```

になる。`deploy.ps1` はこのとき**その環境にあるソリューション一覧をその場で出す**ので、
そこから正しい `Unique Name` を選ぶ。

一覧に出ないなら、**そのテナントではまだアプリをソリューションに入れていない**
（→ [deploy.md](deploy.md) 手順 9）か、**別の環境に繋がっている**。
スクリプトは実行の最初に `pac auth who` で接続先を表示する。

**ソリューション zip は解凍して詰め直さない。** Windows PowerShell 5.1 は .NET Framework で
動き、そこの `ZipFile.CreateFromDirectory` は **zip 内のパス区切りに OS の区切り文字**を使う。
Windows だとエントリ名が `CanvasApps\..._DocumentUri.msapp`（円記号）になり、zip の仕様も
`customizations.xml` の参照も `/` なので、取り込み側がアプリ本体を見つけられず

```
Error: CanvasApp import: FAILURE:
The solution specified an expected assets file but that file was missing or invalid.
```

で落ちる。**macOS / Linux の PowerShell 7 は `/` なので同じスクリプトでも通ってしまい、
手元では再現しない。** `Compress-Archive` も同様に使えない。

`Expand-Archive` 側も怪しい。ソリューション zip には
`[Content_Types].xml`（名前に `[ ]` を含む＝ PowerShell ではワイルドカード）と
`*_BackgroundImageUri`（拡張子が無い）が入っている。

`deploy.ps1` は**解凍せず、zip を開いたまま `.msapp` のエントリだけ入れ替える**。

```powershell
$zip = [System.IO.Compression.ZipFile]::Open($path, 'Update')
$entry = $zip.Entries | Where-Object { $_.FullName -like 'CanvasApps/*.msapp' }
$name = $entry.FullName          # 元の名前をそのまま使う（区切り文字が変わらない）
$entry.Delete()
$new = $zip.CreateEntry($name, 'Optimal')
```

差し替えた後に**元の zip とエントリ名を突き合わせ、落ちたファイルがあれば警告を出す**。

**`deploy.ps1` は UTF-8 BOM 付きで保存してある。消さないこと。**
Windows PowerShell 5.1 は **BOM 無しの `.ps1` を OS の ANSI コードページ**
（日本語環境なら CP932）**として読む**。UTF-8 のまま置くと日本語が

```
throw "繧ｨ繧ｯ繧ｹ繝昴�ｼ繝医↓螟ｱ謨励＠縺溘・
```

のように化け、化けたバイトの中の `\` や `'` が引用符やヒアストリングを壊して
`式またはステートメントのトークン ... を使用できません` が大量に出る。
`.gitattributes` で `*.ps1 text eol=crlf` も指定してある。

**ダブルクォート内でバックティックを使わない。** PowerShell ではエスケープ文字。
`"...`pac auth create`..."` と書くとバックティックが消える。

**リポジトリの `.pa.yaml` はそのままコピーでよい。** `pac canvas unpack` が付ける
先頭のコメントヘッダは無くても pack が通ることを確認済み。

### 毎回の更新（手で叩く場合）

```bash
export PATH="$PATH:$HOME/.dotnet/tools"
export DOTNET_ROOT="/opt/homebrew/opt/dotnet/libexec"

# 1. 取り出す
pac solution export --path ./sol.zip --name <ソリューションの一意名> --overwrite
mkdir solx && cd solx && unzip -q ../sol.zip

# 2. 中の .msapp を YAML に開いて、画面を差し替える
M=CanvasApps/<接頭辞>_<アプリ名>_<id>_DocumentUri.msapp
pac canvas unpack --msapp "$M" --sources s --layout SourceCode
cp ~/mytools/permhub/src/ScrHome.pa.yaml s/Src/ScrHome.pa.yaml   # ヘッダ行の扱いに注意
pac canvas pack --sources s --msapp "$M" --layout SourceCode --overwrite
rm -rf s

# 3. 詰め直して戻す
zip -q -r -X ../sol-mod.zip . && cd ..
pac solution import --path ./sol-mod.zip --force-overwrite --publish-changes
```

`--publish-changes` まで付ければ**公開まで一度に済む**。

> **`Cannot start another [Import] because there is a previous [Import] running`**
> が出ることがある。直前のソリューション操作が裏で走っているだけなので、
> 少し置いて再実行すれば通る（今回は 3 回目までこれが出て、4 回目で通った）。

### 検証したこと

`s/Src/ScrHome.pa.yaml` のタイトルを `"権限申請"` → `"権限申請 [solution経由]"` に変えて
上の 3 手順を実行したところ、**Studio で開いたアプリのヘッダが `権限申請 [solution経由]` に
変わっていた。** 手作業は一切なし。

## `.msapp` の中身

`Src/*.pa.yaml` がそのまま入っている。データソースの定義は `References/DataSources.json`。

```
Header.json  Properties.json
Src\App.pa.yaml  Src\ScrHome.pa.yaml  Src\ScrUser.pa.yaml  Src\ScrReq.pa.yaml
Src\_EditorState.pa.yaml
Controls\*.json
References\DataSources.json  References\Themes.json  References\ModernThemes.json
```

**別テナントへ持っていくときは `References/DataSources.json` が移行元のリストを指している。**
`.msapp` を渡すだけでは繋ぎ直しが必要になる。
