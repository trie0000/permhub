# 権限申請ツール

IT セキュリティ関連の担当者権限を、組織区分に対して付与・変更するアプリ。
Power Apps キャンバスアプリ + SharePoint リスト。**Premium ライセンス不要。**

## 現在の状態

| 機能 | 状態 |
|---|---|
| SharePoint 7 リスト + サンプルデータ | **完了・実機検証済み** |
| ログイン者の特定（Entra ID 突合） | **完了・実機検証済み** |
| 組織マスタ タブ（組織区分1 / 組織区分2 の参照） | **完了** |
| ユーザマスタ タブ（**権限マトリックス**・権限種別切替） | **完了** |
| 申請履歴 タブ（一覧・種別フィルタ） | **完了** |
| 利用者詳細（基本情報・所属・権限の参照） | **完了** |
| 申請詳細（ヘッダ・明細の参照） | **完了** |
| 権限変更の申請書き込み | **完了・実機検証済み** |
| 組織マスタ・利用者マスタの申請書き込み | 未実装 |
| 権限内容の編集（範囲・正副・組織区分2 の変更） | 未実装（表示のみ） |
| Entra ID からの氏名・部署取得 | 未実装（ボタンのみ） |
| 承認フロー | 未実装 |

## 画面

```
┌──────────────────────────────────────────────┐
│ 権限申請                        ログイン者    │
│  組織マスタ │ ユーザマスタ │ 申請履歴        │
│ 組織区分1 [東日本ブロック ▼]  ← 組織/ユーザ内 │
└──────────────────────────────────────────────┘
       ↓ 氏名クリック        ↓ 行クリック
   利用者詳細(ScrUser)    申請詳細(ScrReq)
```

- `ScrHome` — 3 タブ。組織区分1 セレクタは組織マスタ／ユーザマスタ タブの中
  （選んだ値は 3 タブすべてに効く。申請履歴タブにはセレクタを出さない）
- `ScrUser` — 利用者の基本情報・所属タブ・権限マスタ／ディテール
- `ScrReq` — 申請ヘッダと明細（参照専用）

詳細は [docs/screens.md](docs/screens.md)。

## セットアップ

### 1. SharePoint リストを作る

[setup/create-lists.js](setup/create-lists.js) の `SITE_URL` を書き換え、
対象サイトを開いた状態でブラウザのコンソールに貼り付けて実行する（サイト所有者権限が必要）。

`PRM_Org1` / `PRM_Org2` / `PRM_Users` / `PRM_UserOrg1` / `PRM_Grants` /
`PRM_Requests` / `PRM_RequestItems` の 7 本が作られ、索引・一意制約・サンプルデータまで入る。

### 2. アプリを作る

1. 空のキャンバスアプリを作成
2. **設定 → 更新 → 新規 → 「モダン コントロールとモダン テーマ」を ON**
3. **設定 → 表示 → アプリ レイアウトを「レスポンシブ」**
4. データの追加で `PRM_*` 7 本と「Office 365 ユーザー」を接続
5. `App.OnStart` に [src/App.OnStart.txt](src/App.OnStart.txt) を貼る
6. ツリービューで画面を右クリック →「貼り付け」で
   [src/ScrHome.pa.yaml](src/ScrHome.pa.yaml) →
   [src/ScrUser.pa.yaml](src/ScrUser.pa.yaml) →
   [src/ScrReq.pa.yaml](src/ScrReq.pa.yaml) の順に流し込む
7. `App.StartScreen` に `ScrHome` を設定
8. 空の `Screen1` を削除して保存

## ドキュメント

| | |
|---|---|
| [docs/spec-permission.md](docs/spec-permission.md) | 権限仕様（多段階承認の判定、権限6種、範囲、正副） |
| [docs/data-model.md](docs/data-model.md) | リスト構造と履歴の設計 |
| [docs/screens.md](docs/screens.md) | 画面設計 |
| [docs/powerapps-controls.md](docs/powerapps-controls.md) | **モダンコントロールの型名・プロパティ名（実機採取）** |

## 実装で分かった制約

`docs/powerapps-controls.md` に詳細。特に効くもの:

- **型名・プロパティ名は実機から採取する。** 推測すると `PA2101` / `PA2108` で往復する
- **ギャラリーの子で `AddColumns` / `ForAll` の派生列が解決しないことがある。**
  行データは `Title` / `SubTitle` のような単純な文字列に畳んでから渡すのが確実
- **ネストしたギャラリーは動かない。** マトリックスは「行=ギャラリー / 列=固定コントロール」で実現した
- **ギャラリー テンプレート内の絶対 `X` は貼り付け時に書き換えられる。** エラーは出ず表示だけ壊れる。
  列は**横方向 AutoLayout のコンテナー**に入れて `X` を持たせない
- **ギャラリーはレイアウトコンテナーに入れる。** 入れないと貼り付けのたびに `Y` がずれる
- **`ModernText` の `VerticalAlign` は効かない（no-op）。** 縦位置はパディングだけで決まる。
  `PaddingTop = (Height − Size×24/13)/2`（24/13 は実測校正値。`AutoHeight` の 18/13 だと 3px 下がる）。
  枠の高さと `Size` は全て固定なので画面サイズが変わってもズレない
- **高さが違うコントロールを同じ行に並べるときは `Y + Height/2`（中心）を揃える**
- **AutoLayout の子は既定で行の高さいっぱいに伸びる。** 塗りのあるセルは帯に見えるので、
  `AlignInContainer: =AlignInContainer.Center` + `Height` + `LayoutMinHeight: =0` でチップにする
  （列幅を保ったまま細くするには前後に空のスペーサーを挟む）
- `ModernDropdown` に `DefaultSelectedItems` は無い。初期選択は `Default` に**レコード**を渡す
  （`LookUp(col, ...)`。`.NameJa` のような表示文字列を渡すと空表示になる）
- `Appearance` は文字列プロパティ。`ButtonCanvas.FontWeight` は存在しない

## 未確定事項

- **アプリの操作権限**（誰が申請できるか）。現状は所属していれば誰でも申請できる
- 組織区分1・組織区分2 のコード採番規則
- 申請履歴の保持期間（`PRM_RequestItems` は消さないと 5,000 行を超える）
