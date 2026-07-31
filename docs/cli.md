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

| | 今の方式 | `.msapp` 方式 |
|---|---|---|
| 操作 | クリップボードにコピー → 画面を削除 → 貼り付け、を **3 画面ぶん** | ファイルを **1 つ選ぶ** |
| おおよその操作数 | 12〜15 | 3 |

> **未確認**: 取り込みが既存アプリの更新になるのか、新規アプリとして作られるのかは
> 未検証（ブラウザ自動化からローカルファイルを上げられなかったため）。
> 新規アプリになる場合、反復開発には向かず、別テナントへの初回導入向けになる。

## ソリューション経路（検証結果・未完）

完全自動化（`pac solution import` で既存アプリを更新）を試した。**ソリューションに Premium は要らない。**
ただし途中で 2 回つまずいたので、その内容を残す。

### アプリ登録は不要

`pac auth create` の対話ログイン（`Type: User`）のまま `pac canvas download` も
`pac solution list` も通る。**Entra ID のアプリ登録・サービスプリンシパルが要るのは
GitHub Actions などで無人実行するときだけ。**

### ソリューションは普通に作れる

ポータルの「新しいソリューション」で作れる。公開元は既定の `CDS Default Publisher` でよい。

### つまずき① 作りたてのアプリは追加候補に出ない

保存した直後のアプリは「既存を追加 → アプリ → キャンバス アプリ → Dataverse の外部」の
一覧に**出てこない**（検索しても出ない）。**22 分後には出た。** インデックスの反映待ちなので、
慌てて別の原因を疑わないこと。

### つまずき② Studio で開いていると追加できない

一覧から選んで「追加」を押すと、こう出る。

```
'<アプリ名>' is locked by user <ユーザー>. If all authoring sessions for this app
have recently been closed, please wait at least 15 minutes before retrying the operation.
```

**そのアプリを Studio で開いているタブがあると編集ロックがかかる。** タブを閉じて（または
別ページへ移動して）から、しばらく待って再試行する。

### 「特典が不十分」のバナーについて

ソリューション画面には
`この環境への現在の特典が不十分であるため、1 つ以上のコマンドを使用できません`
が常時出ているが、**キャンバスアプリの追加はこれに阻まれていない**
（アプリは選択できて、失敗の理由はロックだった）。バナーが灰色にしているのは別のコマンド。

> **ここまでで未完。** ロック解除待ちのため `pac solution export` → 差し替え →
> `pac solution import` の一周は通していない。**「Premium が要る」は誤り**なので、
> 時間を置いて再試行する価値がある。

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
