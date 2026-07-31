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

Homebrew の dotnet を使っている場合、`pac` が .NET ランタイムを見つけられない。
`DOTNET_ROOT` を指す。

```bash
export DOTNET_ROOT="/opt/homebrew/opt/dotnet/libexec"
```

認証（ブラウザでサインイン画面が出る）。

```bash
pac auth create --name permhub
```

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

## 戻す（`.msapp` → テナント）— ここだけ手作業

`pac canvas` にアップロードは無い。残る道は 2 つ。

| 方法 | 手間 | 備考 |
|---|---|---|
| Studio で `.msapp` を開いて保存 | ファイルを開く数クリック | **画面ごとの貼り付けは不要になる** |
| ソリューションに入れて `pac solution import` | 初期設定が要る | 完全自動化できるが未検証 |

現状はアプリがソリューションに入っていない（`pac solution list` に既定の 2 つしか無い）ため、
ソリューション経路を使うにはまず solution を作ってアプリを追加する必要がある。**未検証。**

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
