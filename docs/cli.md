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

### 毎回の更新（Windows / PowerShell）

[setup/deploy.ps1](../setup/deploy.ps1) を叩くだけ。

```powershell
.\setup\deploy.ps1 -SolutionName permhub
```

やっていること: YAML の重複検査 → `pac solution export` → 中の `.msapp` を展開 →
`src/*.pa.yaml` で画面を差し替え → `pac canvas pack` → zip 詰め直し →
`pac solution import --publish-changes`。

| オプション | |
|---|---|
| `-Screens ScrHome` | 差し替える画面を絞る（既定は ScrHome / ScrUser / ScrReq） |
| `-NoImport` | zip を作るところで止める。中身を見たいとき |
| `-SrcDir <path>` | 差し替え元を変える（既定は `src`） |

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

**`Compress-Archive` は使っていない。** ソリューション zip は中身がルート直下に
並んでいる必要があり、`[System.IO.Compression.ZipFile]::CreateFromDirectory` のほうが確実。

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
