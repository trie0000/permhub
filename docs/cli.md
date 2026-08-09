# Power Platform CLI での取り回し（permhub 固有）

画面ごとにツリービューへ貼り付ける作業をやめ、`pac`（Power Platform CLI）で
`.msapp` と YAML を往復する。**このページは permhub 固有の運用だけを扱う。**

> **環境構築（.NET SDK 10・`DOTNET_ROOT`・`pac auth`）と、アプリに依存しない罠は Notion にある。**
> [🔁 pac CLI で既存アプリを更新する（環境構築と罠）](https://app.notion.com/p/3b56a1cf2b798188bbbff40fabeb9cc6)
>
> ソリューション経由の初回準備、**取り込んだだけでは公開されない**件、公開に
> Windows PowerShell 5.1 が要る件、zip のパス区切りの罠、`.ps1` の BOM、
> サービスプリンシパルでの無人実行、`.msapp` の中身は向こうを見る。
> **新しく別の Power Apps アプリを立てるときも向こうから読む。**

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

`pac canvas pack` は壊れた YAML を素通しする（→ Notion §6）。そこで自前で見る。

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

## 戻し方の選択肢

`pac canvas` にアップロードコマンドは無い。取り込みは UI から行う。

**アプリ一覧 →「アプリをインポートする」→「ファイルから (.msapp)」**（実在を確認済み）。
Studio の「…」メニューには「アプリのバージョン履歴」しか無く、**Studio 側から
ローカルの `.msapp` を開く導線は無い**。

| | 貼り付け方式 | `.msapp` 取り込み | ソリューション経由 |
|---|---|---|---|
| 操作 | コピー → 画面削除 → 貼り付け ×3 画面 | ファイルを 1 つ選ぶ | **コマンドのみ** |
| 操作数 | 12〜15 | 3 | 0 |
| 結果 | 既存アプリを更新 | **新規アプリになる** | **既存アプリを更新** |
| 向く用途 | — | 別テナントへの初回導入 | **反復開発** |

> **未確認**: 取り込みが既存アプリの更新になるのか、新規アプリとして作られるのかは
> 未検証（ブラウザ自動化からローカルファイルを上げられなかったため）。

**permhub はソリューション経由を使う。** 前提と初回準備は Notion 側。

## 毎回の更新

[setup/deploy.ps1](../setup/deploy.ps1) を叩くだけ。

```powershell
.\setup\deploy.ps1 -SolutionName permhub
```

### 動かすのに要るもの

`pac` は .NET のツールなので、**`DOTNET_ROOT` が通っていないと起動もしない**。
`You must install .NET to run this application.` で落ちたらこれ。

| | `DOTNET_ROOT` |
|---|---|
| macOS（Homebrew） | `/opt/homebrew/Cellar/dotnet/<版>/libexec` |
| WSL / Linux | `$HOME/.dotnet` |

`pac` の**認証プロファイルは機械ごと**。`pac auth list` で `No profiles were found`
なら、その機械では `pac auth create` がまだ。**別の機械で作ったプロファイルは使えない。**

スクリプト本体は PowerShell 7 で動かす。Windows PowerShell 5.1 だと
`$IsWindows` が無いため、`pac` が見つからないときの案内でそのまま落ちる。

```bash
export DOTNET_ROOT=/opt/homebrew/Cellar/dotnet/10.0.108/libexec
export PATH="$PATH:$HOME/.dotnet/tools"
pwsh -NoProfile -File setup/deploy.ps1 -SolutionName permhub -WithApp
```

### 公開だけは Windows PowerShell 5.1

`Publish-PowerApp` は `Microsoft.PowerApps.PowerShell` にしかなく、
**このモジュールは PowerShell 7 では動かない**。macOS で動かすと
`! Windows PowerShell 5.1 が無いので公開できない` で公開だけ飛ぶ。

そうなると**保存版は新しいのに、利用者に配られる公開版は古いまま**になる。
WSL がある環境なら、取り込みまでを macOS、公開だけを WSL 経由で叩けばよい。

```bash
. ~/.permhub-env
export WSLENV="${WSLENV:+$WSLENV:}PERMHUB_SP_TENANT:PERMHUB_SP_APPID:PERMHUB_SP_SECRET"
powershell.exe -NoProfile -Command "…; Publish-PowerApp -AppName <アプリID>"
```

**`409 Conflict` が返るのは、誰かが Studio でそのアプリを開いているとき。**
タブを閉じてから叩き直す。`Write-Output` を成功の合図にしないこと。
戻り値の `Code` を見る。

### アプリの状態を確かめるときは公開後に

`pac solution export` も `Get-AdminPowerApp` の `connectionReferences` も、
**公開された版**を返す。Studio で保存しただけの変更は出てこない。

公開が `409` で止まっている間にこれを見ると、いつまでも古い一覧が返る。
**「保存したのに反映されない」と思ったら、まず公開が通っているか確かめる。**

Studio 自身もアプリを強くキャッシュする。ハードリロードでも「すべて再確認」でも
古い版が残ることがあるので、**確実なのはタブを閉じて開き直すこと**。
手元と食い違うときは、エクスポートして中身を突き合わせるのが早い。

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
`pac solution import --publish-changes` → 公開。

| オプション | |
|---|---|
| `-Screens ScrHome` | 差し替える画面を絞る（既定は ScrHome / ScrUser / ScrReq） |
| `-WithApp` | `App.Formulas` と `App.OnStart` も反映する（下記） |
| `-PruneScreens` | `src` に無い画面をアプリから削除する（下記） |
| `-NoImport` | zip を作るところで止める。中身を見たいとき |
| `-NoPublish` | 公開を飛ばす。Studio で自分で公開するとき |
| `-SrcDir <path>` | 差し替え元を変える（既定は `src`） |

**`-SolutionName` に渡すのは「一意名」**（表示名ではない）。違う名前を渡すと
`Error: The given solution unique name (xxx) is not valid` になる。`deploy.ps1` は
このとき**その環境にあるソリューション一覧をその場で出す**ので、そこから正しい
`Unique Name` を選ぶ。

一覧に出ないなら、**そのテナントではまだアプリをソリューションに入れていない**
（→ [deploy.md](deploy.md) 手順 9）か、**別の環境に繋がっている**。
スクリプトは実行の最初に `pac auth who` で接続先を表示する。

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

`-NoDataSourceCheck` で止めずに進められる。

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
.\setup\deploy.ps1 -SolutionName permhub -WithApp
```

### `src` に無い画面が残っているとき

そのテナントのアプリに `src` に無い画面が残っていて、そこに同じ名前のコントロールが
あると、取り込みが落ちる（コントロール名はアプリ全体で一意）。

```
Src\ScrHome.pa.yaml(70,7) : error PA2110 : An entity with name 'drpOrg1'
already exists. Other definition located at Src\ScrEdit.pa.yaml(194,9).
```

`deploy.ps1` は展開した時点で `src` に無い画面を見つけ、**コントロール名がぶつかって
いるものだけを並べて止める**。ぶつかっていなければそのまま残して続ける。

その画面が要らないなら消してから反映する。**アプリからその画面が消える**ので、
中身が要らないことを確かめてから。

```powershell
.\setup\deploy.ps1 -SolutionName permhub -PruneScreens
```

残したいなら、Studio でその画面のコントロールを重ならない名前に変える。

> 画面を消して `pac canvas pack` しても通ることは確認済み。`_EditorState.pa.yaml` が
> その画面を参照したままでも pack が畳んでくれる。

**リポジトリの `.pa.yaml` はそのままコピーでよい。** `pac canvas unpack` が付ける
先頭のコメントヘッダは無くても pack が通ることを確認済み。

## 毎回の更新（手で叩く場合）

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

**この手順は macOS / Linux でしか使わないこと。** Windows PowerShell から
`Compress-Archive` で詰め直すと zip 内のパス区切りが壊れて取り込みが落ちる（→ Notion §4）。

## 検証したこと

`s/Src/ScrHome.pa.yaml` のタイトルを `"権限申請"` → `"権限申請 [solution経由]"` に変えて
上の 3 手順を実行したところ、**Studio で開いたアプリのヘッダが `権限申請 [solution経由]` に
変わっていた。** 手作業は一切なし。
