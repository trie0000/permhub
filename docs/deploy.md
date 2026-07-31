# 別テナントへの導入手順

このリポジトリのソースから、別の Microsoft 365 テナントに同じアプリを立てる手順。
アプリは `.msapp` を配るのではなく、**`src/` のテキストを新しいアプリに貼って作る**。

## 先に用意するもの（ここが埋まっていないと途中で止まる）

| | 何 | 取り方 |
|---|---|---|
| □ | 対象 SharePoint サイトの URL | 新規にサイトを作るなら先に作る |
| □ | そのサイトの**所有者権限**があるアカウント | セットアップスクリプトが列を作る |
| □ | 管理者にする Teams（Microsoft 365 グループ）の ID | `DO.adminMe` ならサイト自身のグループを使う。別にするなら手順 3 |
| □ | **自分の Entra ID オブジェクト ID** | `DO.bindMe` が自動で取る。手で入れるなら手順 2。**これが無いとアプリが空で開く** |
| □ | Power Apps 環境（モダンコントロールを ON にできること） | 環境の言語も確認する（手順 5） |
| □ | 初期データを入れるか、ダミーで動かすか | 手順 1 の `DO.seed` |

## 1. SharePoint を用意する

[setup/setup.js](../setup/setup.js) を 1 回貼って実行するだけ。
**リスト 8 本・列・索引・一意制約・ダミーのマスタ・自分の紐付け・管理者グループ**が揃う。

先頭の 2 か所を直す。

```js
const SITE_URL = "https://YOUR-TENANT.sharepoint.com/sites/YOUR-SITE";

const DO = {
  lists:    true,  // リスト 8 本・列・索引・一意制約
  seed:     true,  // ダミーのマスタ（本番では false）
  bindMe:   true,  // 今ログインしている自分を BIND_GID の利用者に紐づける
  adminMe:  true,  // このサイトの Microsoft 365 グループを管理者グループにする
  backfill: false, // 承認機能より前に作ったサイトの後始末
};
```

| 用途 | `DO` |
|---|---|
| **検証環境**（空サイトに一発で動くものを作る） | 既定のまま |
| **本番**（実データを自分で入れる） | `seed` / `bindMe` / `adminMe` を `false`。手順 2・3 を手でやる |
| **既存サイトの更新**（列だけ足す） | `lists` だけ `true` |

対象サイトを開いた状態で DevTools のコンソールに全文を貼り付けて実行する
（サイト所有者権限が必要）。**何度実行しても安全**で、既にあるリスト・列・選択肢・行は飛ばす。

## 2. ログイン者の紐付け（`bindMe` を `false` にしたとき）

アプリは **ログイン中のユーザを Entra ID のオブジェクト ID で `PRM_Users` から引く**。

```
Set(gblMyAdId, Office365ユーザー.MyProfileV2().id);
Set(gblMe, LookUp(PRM_Users, AdObjectId = gblMyAdId));
Set(gblMeGid, If(IsBlank(gblMe.Title), "1234567", gblMe.Title));
```

引けないと `gblMeGid` が `"1234567"` に落ちる。新しいテナントにその ID の人は居ないので、
**所属が 1 件も取れず、組織マスタもユーザマスタも空で開く**。

`bindMe: true` ならスクリプトが自動でやる（SharePoint のユーザープロファイル
`msOnline-ObjectId` を読んで `PRM_Users` に書く）。手でやる場合は次を入れる。

| リスト | 入れる行 |
|---|---|
| `PRM_Org1` | 組織区分1 を 1 件以上（`Title` = コード、`NameJa`、`SortOrder`、`IsActive` = はい、`MsExt`/`MsWlan`/`MsCloud`） |
| `PRM_Org2` | その配下の組織区分2（`Title` = コード、`Org1Code`、`NameJa`、`SortOrder`、`ApExt`/`ApWlan`/`ApCloud`、`IsActive` = はい） |
| `PRM_Users` | 自分（`Title` = グローバルID、`FullName`、**`AdObjectId`**、`IsActive` = はい） |
| `PRM_UserOrg1` | `Title` = `<グローバルID>#<組織区分1コード>`、`GlobalId`、`Org1Code`、`IsActive` = はい |

オブジェクト ID は Entra ID 管理センターのユーザー詳細「オブジェクト ID」、または
対象サイトのコンソールで次を実行しても取れる。

```js
(await (await fetch("/_api/SP.UserProfiles.PeopleManager/GetMyProperties?$select=UserProfileProperties",
  { headers: { Accept: "application/json;odata=nometadata" } })).json())
  .UserProfileProperties.find(p => p.Key === "msOnline-ObjectId").Value
```

### 本番に出す前にフォールバックを外す

`"1234567"` のままだと、マスタ未登録の人が**全員そのグローバルIDとして申請できてしまう**。
本番テナントでは `App.OnStart` のこの箇所を空文字にして、
未登録なら申請させない作りに変えること（現状は未実装。ヘッダには「未登録」と出るだけ）。

## 3. 管理者グループ（`adminMe` を `false` にしたとき）

`PRM_Config` の `AdminGroupId` 行の `Value` に、管理者にする Teams（Microsoft 365 グループ）の
ID を入れる。そのチームの SharePoint サイトで `/_api/site?$select=GroupId` を開けば分かる。

`adminMe: true` なら、**スクリプトを流したサイト自身のグループ**が設定される
（そのチームのメンバー全員が管理者になる）。別のグループにしたいときは手で入れ直す。

空のままだと申請履歴・申請詳細に **確認中／完了／差し戻し が出ない**
（＝誰も申請を完了にできず、マスタに反映されない）。申請と取り下げはできる。

## 4. アプリの器を作る

1. 空のキャンバスアプリを作る
2. **設定 → 更新 → 新規 →「モダン コントロールとモダン テーマ」を ON**
3. **設定 → 表示 → アプリ レイアウトを「レスポンシブ」**
4. データの追加で以下を接続する
   - SharePoint：手順 1 のサイトから `PRM_*` **8 本**（`PRM_Config` を含む）
   - **Office 365 ユーザー**
   - **Office 365 グループ**

## 5. コネクタ名を環境の言語に合わせる

**コネクタの参照名は環境の表示言語になる。** 日本語環境で採取したソースは
`Office365ユーザー` / `Office365グループ` と書いてある。英語環境なら
`Office365Users` / `Office365Groups`。このまま貼ると名前エラーになる。

数式バーで `Office365` と打って実際の候補名を確認し、貼る前に置換する。

```bash
sed -i '' 's/Office365ユーザー/Office365Users/g; s/Office365グループ/Office365Groups/g' src/App.OnStart.txt
```

使っているのは `App.OnStart` の 2 か所だけ（`MyProfileV2` と `ListGroupMembers`）。

## 6. ソースを流し込む

**順番を守る。** 画面は `App.Formulas` の名前付き数式を参照している。

| # | 貼り先 | ソース |
|---|---|---|
| 1 | `App.Formulas` | [src/App.Formulas.txt](../src/App.Formulas.txt) |
| 2 | `App.OnStart` | [src/App.OnStart.txt](../src/App.OnStart.txt) |
| 3 | 画面 | [src/ScrHome.pa.yaml](../src/ScrHome.pa.yaml) |
| 4 | 画面 | [src/ScrUser.pa.yaml](../src/ScrUser.pa.yaml) |
| 5 | 画面 | [src/ScrReq.pa.yaml](../src/ScrReq.pa.yaml) |

クリップボードへは文字コードを指定して入れる（`pbcopy` は既定で UTF-8 にならない）。

```bash
LC_CTYPE=UTF-8 pbcopy < src/ScrHome.pa.yaml
```

画面は**ツリービューで既存の画面の「…」→「貼り付け」**で入る。
1〜2 は数式バーに `Cmd+A` → `Delete` → `Cmd+V`。

仕上げ:

1. `App.StartScreen` に `ScrHome` を設定
2. 空の `Screen1` を削除
3. **アプリのチェック → 数式 のエラーを 0 にする**（エラーのあるプロパティは黙って実行されない）
4. 保存
5. **App を右クリック →「OnStart を実行します」**（貼り替えても、プレビューでも自動では走らない）

## 7. 通しで確認する

- [ ] ヘッダ右上に**自分の氏名とグローバルID**が出る（「未登録」なら手順 2 に戻る）
- [ ] 組織マスタに組織区分1 の要否と組織区分2 の一覧が出る
- [ ] ユーザマスタのマトリックスに人が並ぶ
- [ ] 管理者アカウントなら、申請履歴の行に 確認中／完了／差し戻し が出る
- [ ] 要否を 1 つ変える → `申請明細` に 1 件出る → `申請` → 申請履歴に載る
- [ ] その申請を開いて `完了にする` → **SharePoint のリストが書き換わる**
- [ ] 検証で入れた変更を元に戻す

## 8. 共有と SharePoint の権限

Power Apps 側の共有に加えて、**SharePoint リスト側の権限が要る**。アプリは
ログインユーザーの権限でリストを読み書きするため。

| | `PRM_Org1` / `Org2` / `Users` / `UserOrg1` / `Grants` / `Config` | `PRM_Requests` / `PRM_RequestItems` |
|---|---|---|
| 申請者 | 読み取り | 編集（申請の書き込みと取り下げ） |
| 管理者 | **編集**（完了時にマスタを書く） | 編集 |

> 権限を絞ったアカウントでの動作確認は未実施。最初は全員編集で通し、
> 絞るときはこの表を出発点にする。

## 9. テナントに合わせて直す前提値

そのままでは合わない可能性が高い箇所。**手順 6 の前にソースを直す**方が、
あとから Studio で追うより早い。

| 前提 | 今の値 | 直す場所 |
|---|---|---|
| 権限 6 種のコードと名称 | `SECMGR` 事業場ITセキュリティ責任者 / `CONFORM` 適合化担当 / `EXTCONN` 外部接続申請担当 / `WLAN` 無線LAN申請担当 / `CLOUD` クラウド申請担当 / `INFOSEC` 情報セキュリティ担当 | `App.Formulas` の `fRoles`、`ScrHome` の権限種別タブ、`ScrUser` の役割行。**種類を増減するならコントロールの追加・削除が要る**（1 種別 = 1 コントロール） |
| グローバルID の書式 | 数字 7 桁 または 英字 1 桁 + 数字 6 桁 | `ScrUser` の `IsMatch(gblNewGid, "^([0-9]{7}\|[A-Z][0-9]{6})$")` |
| 組織区分2 のコード採番 | `"A"` + 組織区分1 コードの下 2 桁 + 連番 2 桁（`B01` → `A0101`） | `App.Formulas` の `fO2NextCode` |
| 多段階承認の 3 種 | 外部接続 / 無線LAN / クラウド | 列そのもの（`PRM_Org1.MsExt/MsWlan/MsCloud`、`PRM_Org2.ApExt/ApWlan/ApCloud`）。増減はスキーマ変更 |
| 未登録者のフォールバック | `"1234567"` | `App.OnStart`（手順 2） |
| 申請履歴の取得範囲 | 直近 365 日 | `App.OnStart` の `DateAdd(Now(), -365, TimeUnit.Days)` |

## 10. 引っかかりやすいところ

- **SharePoint に列や選択肢を足したら、Power Apps 側でデータソースを「最新の情報に更新」する。**
  しないと `名前が無効です: 'ItemStatus' は認識されません` になる
- **`App.OnStart` は貼り替えても自動では走らない。** プレビュー（▷）でも再実行されない
- **コントロール名はアプリ全体で一意。** 既存の画面と名前が衝突すると、貼り付け時に黙って `_1` が付く。
  貼る前に古い画面を消す
- **`App.Formulas` は定義ごとに `;` で終える。** 末尾に追記して直前の `;` を落とすと、
  その定義が丸ごと消えて「名前が無効です」が全画面に出る
- **`PRM_RequestItems` は消さないと 5,000 行を超える。** 保持期間の運用を決めておく
- 詳しい制約は [powerapps-controls.md](powerapps-controls.md) と [README](../README.md) の「実装で分かった制約」
