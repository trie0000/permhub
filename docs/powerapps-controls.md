# このアプリで使うコントロールの正確な型名・プロパティ名

**実機で採取したもの。推測で書かない。** 採取方法はツリービューで右クリック →「コードを表示」。

## 型名（モダンコントロール ON の環境）

| 挿入ペインの名前 | YAML の型名 |
|---|---|
| テキスト | `ModernText@1.0.0` |
| ボタン | `ModernButton@1.0.0` |
| ドロップダウン | `ModernDropdown@1.0.2` |
| 垂直ギャラリー | `Gallery@2.15.0` |
| コンテナー | `GroupContainer@1.5.0`（`Variant: AutoLayout`） |

**間違えた例（PA2101 になる）:** `Label@2.5.1` / `Button@0.0.45` / `DropDownCanvas`

## `ModernText` のプロパティ

`Color` `ContentLanguage` `DisplayMode` `Fill` `Font` `FontWeight` `Height` `Italic`
`OnSelect` `PaddingBottom` `PaddingLeft` `PaddingRight` `PaddingTop`
`RadiusBottomLeft` `RadiusBottomRight` `RadiusTopLeft` `RadiusTopRight`
`Size` `Strikethrough` `Text` `Underline` `Visible` `Width` `Wrap` `X` `Y`
`BorderColor` `BorderStyle` `BorderThickness` `Align` `VerticalAlign`

**間違えた例（PA2108 になる）:** `FontColor` / `FontSize`
→ 正しくは **`Color`** と **`Size`**。クラシックの `Label` と同じ名前。

**`RadiusTopLeft` 等がある** = モダンテキストは角丸にできる。
クラシックの `Rectangle` にはこれが無いので、色付きの帯や角丸カードは
**`ModernText`（Text は空文字）で作る**のが早い。

## 採取の手順

1. 挿入ペインからコントロールを 1 つ置く
2. ツリービューで画面を右クリック →「コードを表示」→ 型名を読む
3. コントロールを選択し、**数式バー左のプロパティ ドロップダウン**を開く → プロパティ名の全一覧が出る

この 3 手を先にやれば、`PA2101` / `PA2108` の往復をしなくて済む。

## 列挙値の書き方（実機で確認）

**列挙名もメンバー名も推測してはいけない。** プロパティ名が合っていても列挙名が違うと
「名前が無効です」＝**そのプロパティは数式エラーになり、既定値で描画される**。
エラーはキャンバス上の赤い ⊗ バッジと **アプリのチェック → 数式 → エラー** にしか出ないので、
プレビューが「なんとなく動いている」だけでは気づけない。

```
Appearance:    ='ButtonCanvas.Appearance'.Primary
Align:         ='TextCanvas.Align'.Start      ← Left ではない
VerticalAlign: =VerticalAlign.Middle          ← TextCanvas 名前空間には無い（クラシック列挙）
FontWeight:    ='TextCanvas.Weight'.Bold      ← TextCanvas.FontWeight ではない
```

`ModernText` の列挙は**この 2 つだけ**（数式バーで `'TextCanvas.` と打つと候補が出る）:

| 列挙 | メンバー |
|---|---|
| `'TextCanvas.Align'` | `Start` / `Center` / `End` / `Justify`（**`Left` / `Right` は無い**） |
| `'TextCanvas.Weight'` | `Regular` / `Medium` / `Semibold` / `Bold`（**`Normal` は無い**） |

`VerticalAlign` はプロパティとしては存在するが、値はクラシックの
`VerticalAlign.Top` / `.Middle` / `.Bottom` を使う。

`ModernButton` にも `Color` / `Align` / `FontWeight` / `Fill` / `Icon` / `Layout` がある。

### 列挙名を実機から採取する 2 手

1. 数式バーで `'TextCanvas.` まで打つ → その名前空間の**列挙一覧**が出る
2. `'TextCanvas.Align'.` まで打つ → **メンバー一覧**が出る（確定すると
   `'TextCanvas.Align'.End = End / データ型: テキスト` と型ヒントが出る）

名前空間が分からない列挙は、クラシック名（`VerticalAlign.` `NotificationType.` など）も試す。

### やらかした実例

`'TextCanvas.Align'.Left` / `.Right` と `'TextCanvas.FontWeight'.*` を全画面で使っていて、
**数式エラーが 400 件**たまっていた（1 つの無効な列挙につき「名前が無効です」＋
「演算子 '.' は Error の値で使用できません」の 2 件）。症状は:

- 左寄せ・右寄せがすべて既定（`Start`）で描画される
- **太字がどこにも効かない**
- `VerticalAlign` が効かない → 「no-op だ」と誤診し、パディングで中央寄せする回避策を約 170 個書いた

修正後はエラー 0 件。**アプリのチェック → 数式 → エラー を最初に 0 にしてから**
見た目の調整に入ること。`ランタイム` タブだけ見ても数式エラーは出てこない。

## `ModernDropdown` は `ItemDisplayText` が必須

レコードのテーブルを `Items` に渡すとき、これが無いと**選択肢が空欄で並ぶ**
（デザイナにエラーマークが出る）。

```
Items:           =colMyOrg1
ItemDisplayText: =ThisItem.NameJa
OnChange:        =Set(gblOrg1, drpOrg1.Selected.Title)
```

## 追加で採取した型名

| 挿入ペイン | YAML の型名 |
|---|---|
| テキスト入力 | `ModernTextInput@1.1.1` |

`Default` / `Placeholder` / `MaxLength` / `OnChange` / `DisplayMode` を持つ。
**読み取りは `.Text`**（`.Value` ではない）。

## `Appearance` は文字列プロパティ

ヒントに `'ButtonCanvas.Appearance'.Transparent = Transparent` / **データ型: テキスト** と出る。
列挙構文も通るが、素直に文字列で書くのが安全。

```
Appearance: ="Transparent"   （Outline / Primary / Secondary / Subtle / Transparent）
```

**`ButtonCanvas.FontWeight` は存在しない。** `If()` の中で使うと式全体が失敗し、
`Appearance` まで既定に戻る（ボタンが青くなる）。
太字の出し分けが要るタブ等は **`ModernText` + `OnSelect`** で作る方が確実。

## マトリックス表示は「固定列」で作る

**ネストギャラリーは動かない。`AddColumns` / `ForAll` の派生列もギャラリーの子で解決しない。**
両方を回避する唯一の形が「行はギャラリー、列は固定コントロール」。

```
galMx.Items = Sort(Filter(colOrg2All, Org1Code = gblOrg1), SortOrder)   ← 実在のリストレコード
  子: mxRowName = ThisItem.NameJa      ← 実在フィールドは解決する
      mxC1 .. mxC8                     ← 列ぶんの固定セル（内側ギャラリーを作らない）
```

セルの式は **`ThisItem.<実在フィールド>`** と **画面レベルの式** だけで組む。

```
mxC3.Text =
  If(IsBlank(Index(<ページ内メンバー>, 3).GlobalId), "",
  If(!(<この行が対象かの判定>), "―",
  If(IsBlank(<その人の権限>.GlobalId), "",
  If(<その人の権限>.ScopeType.Value = "ALL", "◎",
  If(";" & ThisItem.Title & ";" in <その人の権限>.Org2Codes, "○", "")))))
```

- `ThisItem.Title` を複雑な式の中で使うのは問題ない（解決する）
- 列見出しも同じ数の固定コントロールにして X 座標を揃える
- **列数は固定**になる。可変にしたければページングで割り切る

### 失敗した順序（同じ轍を踏まないために）

1. ネストギャラリー → 内側の子が `ThisItem.Mark` を解決しない
2. `WrapCount` で平坦化 → セルが描画されない
3. `AddColumns` で結合 → 派生列が子で解決しない
4. **固定列 → 成功**

## ギャラリーの列は「横方向 AutoLayout」で並べる（絶対 X を使わない）

**ギャラリー テンプレート内の子の `X` は、貼り付け時に切り詰められる。**
テンプレート幅に収まらない `X` が黙って別の値に書き換えられる。
しかも閾値が貼り付けのたびに変わる（`X=624` が `542` になった回もあれば、`X=936` が `0` になった回もある）。
**エラーにならず、見た目だけが壊れる**ので気づきにくい。

実際にこれで、マトリックスの 5〜8 列目が 1 か所に重なり、
**別人の権限が隣の人の列に表示されていた**（保存も貼り直しも成功していたので長く気づけなかった）。

対策は **行を横方向 AutoLayout のコンテナーにして、子に X を持たせない**こと。

```yaml
galMx:
  Control: Gallery@2.15.0
  Children:
    - mxRow:
        Control: GroupContainer@1.5.0
        Variant: AutoLayout
        Properties:
          X: =0                    # 0 なので切り詰められない
          Y: =0
          Width: =Parent.TemplateWidth
          Height: =46
          LayoutDirection: =LayoutDirection.Horizontal
          LayoutAlignItems: =LayoutAlignItems.Stretch
          PaddingLeft: =0          # 4 辺とも 0（既定だと列がずれる）
        Children:                  # 記述順 = 左からの並び順
          - mxRowName:  FillPortions: =0 / Width: =150
          - mxRowCode:  FillPortions: =0 / Width: =58
          - mxC1..mxC8: FillPortions: =0 / Width: =130
    - mxRowRule:                   # X=0 の全幅コントロールは行外に置いてよい
        Properties: { X: =0, Y: =45, Width: =Parent.TemplateWidth }
```

- **列幅は固定値にする。** `FillPortions: =1` で等分すると、行の幅が貼り付けのたびに揺れて
  画面レベルの見出しとずれる。固定値なら見出し X も `252 + n*130` で決め打ちできる
- 見出しはギャラリーの外（画面レベル）なので、`X` は切り詰められない

### `X` に `Parent.TemplateWidth` は使えない

`Width` では使えるが、**`X` に書くと式が失敗して `X=1` に落ちる**。

```
Width: =(Parent.TemplateWidth - 208) / 8            OK
X:     =208 + (Parent.TemplateWidth - 208) / 8 * 4  NG（X が 1 になる）
```

### ギャラリーに `Width` を明示しても防げない

貼り付け前に `galMx.Width: =1278` を入れても切り詰めは起きた。**AutoLayout 化以外に回避策はない。**

## `ModernText` の縦位置とスクロールバー

### 縦中央寄せは `VerticalAlign.Middle` の 1 行で足りる

```
PaddingTop:    =0
PaddingBottom: =0
VerticalAlign: =VerticalAlign.Middle
```

枠の `Height` にも `Size` にも依存しないので、**高さを変えても再調整は不要**。
複数行に折り返すテキストでもブロックごと中央に来る。

`Height` と `Size` を変えたときに壊れないので、テキスト枠は**全部これで統一してよい**
（このリポジトリでは `ModernText` 226 個すべてがこの形）。

### パディングの既定値 5+5 はスクロールバーの原因

パディングを 0 にすると内容高さは行高だけになるので、行が枠に収まる限り
スクロールバーは出ない。逆に既定の 5+5 のままだと `Height: =28` / `Size: =15` で
内容領域が 18px しか残らず**スクロールバーが出る**。

### 誤診の記録（同じ穴に落ちないために）

> `VerticalAlign` を「効かない no-op」と 2 回結論づけたが、**どちらも誤り**だった。
> 原因は列挙名 `'TextCanvas.VerticalAlign'.Middle` が**存在しない**こと
> （正しくは `VerticalAlign.Middle`）。プロパティが数式エラーになって既定値
> ＝上寄せで描画されていただけ。
>
> - 1 回目: 「`Wrap: =false` が `VerticalAlign` を無効化している」→ 誤り
> - 2 回目: `Middle` と `Bottom` を並べて「同じ位置に描画された」→ **両方ともエラーで既定値**だった
> - その結果 `PaddingTop = (Height − Size×24/13)/2` という校正式を約 170 箇所に手で入れた
>
> **見た目が期待と違うときは、まず アプリのチェック → 数式 → エラー を見る。**
> 描画の推測から入ると、無効な列挙名は「その機能が無い」ようにしか見えない。

### 高さの違うコントロールを同じ行に並べるとき

**中央寄せでは `Y + Height/2`（中心）が揃っていないとズレる**（上詰めなら `Y` を揃えれば済んだ）。
行見出しなど高さの違うものを横に並べている箇所は中心で合わせる。

```
中心 = Y + Height / 2      ← 同じ行に見せたいものはこれを一致させる
```

## `ModernDropdown@1.0.2` の初期選択

`DefaultSelectedItems` は**無い**（`PA2108` になる）。初期選択は **`Default`** で行う。

**`Default` には表示テキストの文字列ではなく、`Items` の中の「レコード」を渡す。** ここを間違えると空表示になる。

```
Items:   =colMyOrg1
Default: =LookUp(colMyOrg1, Title = gblOrg1)          ← レコード。これで初期選択が出る
                                                        （データ型: レコード）
OnChange:=Set(gblOrg1, Self.Selected.Title)
```

`Default: =LookUp(colMyOrg1, Title = gblOrg1).NameJa`（**表示文字列**）だと、
`Items` に一致テキストがあっても**選択されず空欄のまま**になる。実機で確認済み。

> **検証の注意:** Studio のプレビューは前回のセッション状態を再開し、`App.OnStart` を毎回は再実行しない。
> `Default` は `OnStart` で入れた変数に依存するので、確認前に **App の「OnStart を実行」→ ▷ プレビュー**の順で
> 起動し直す（画面が `OnStart` 既定のタブで開けば新規実行できている）。

## 重い式は `App.Formulas`（名前付き数式）に括り出す（性能の要）

Power Apps はコントロールのプロパティを**書いてある回数だけ**評価する。同じ式を
コピーして並べると、そのぶん丸ごと再計算される。マトリックスはこれで操作不能に重かった。

```
# 1 セルの Text/Color がそれぞれ実行していたもの
Filter(colMemberAll, ...) × 9      ← ページ内 8 人の GlobalId を出すためのチェーン
LookUp(colOrg1, ...)      × 6      ← 多段階設定の要否
LookUp(colGEdit, ...)     × 1
```

セル 56 個 + ヘッダ 24 個ぶんが**毎レンダリング**走る。名前付き数式に括り出すと
**結果がキャッシュされ、依存（`gblOrg1` / `gblPage` / コレクション）が変わったときだけ再計算**される。

```
# App.Formulas
fMem  = Filter(colMemberAll, Org1Code = gblOrg1);
fPage = FirstN(LastN(fMem, CountRows(fMem) - gblPage * 8), 8);
fG1   = If(CountRows(fPage) >= 1, Index(fPage, 1).GlobalId, "");   … fG8 まで
fP1   = LookUp(colOrg1, Title = gblOrg1);
fChg  = Filter(ForAll(Filter(colGEdit, O1 = gblOrg1) As e, …), Chg);
```

実測: `ScrHome` は 219KB → 146KB、`Filter(colMemberAll, …)` の出現が **740 → 0**。
権限種別の切り替えもページ送りも、クリック直後のスクリーンショットで既に再描画が終わっている。

**要点**
- 名前付き数式は**グローバル変数もコレクションも依存にできる**（どちらも変更を検知して再計算される）
- **副作用は書けない**（`Set` / `Collect` / `Patch` は不可）。純粋な式だけ
- 順番に依存してよい（`fPage` が `fMem` を参照するなど）。定義順は問わない
- 変数と違って**初期化のタイミングを気にしなくてよい**。`OnStart` の非同期読み込みが
  終わっていなくても、コレクションが埋まった時点で自動的に再計算される
  （`Set(gblP1, LookUp(...))` を `OnVisible` でやっていたときは、この初期化レースで
  マトリックスが全部 `―` になる不具合が出ていた）
- **画面より先に `App.Formulas` を設定する。** 画面が参照する名前が無いと貼り付け時にエラーになる

同じ理屈で、データソースへの `LookUp` を画面に散らすとその回数だけ通信が起きる
（`ScrReq` は `LookUp(PRM_Requests, Title = gblReqNo)` を 13 箇所に書いていた）。

## 数式エラーのあるプロパティは「実行されない」

`OnSelect` に数式エラーがあると、**そのボタンはクリックしても何も起きない**。
エラーも通知も出ず、`Visible` / `Fill` / `Text` は正常に評価されるので、
見た目は完全に正常なボタンに見える。

`btnGrantSubmit` がこれに当たり、原因はスコープ名の衝突だった。

```
# NG: LookUp のスコープ内では c が「テーブルの列 c」になり、With 変数の c が隠れる
ForAll(Sequence(N) As i, With({c: Index(colGChg, i.Value)},
  ... LookUp(Table({c:"WLAN", n:"無線LAN申請担当"}, ...), c = c.Role).n ...))

# OK: インラインテーブルの列名を別名にする
  ... LookUp(Table({rc:"WLAN", rn:"無線LAN申請担当"}, ...), rc = c.Role).rn ...
```

**クリックしても無反応なコントロールを見つけたら、Z オーダーや当たり判定を疑う前に
そのコントロールの赤い ⊗ バッジ →「数式バーで編集」で当該プロパティを開く。**

## 貼り付け時の注意

- 数式バー左の**プロパティ名コンボにフォーカスが残っていると `Cmd+V` がそこに入る**。
  ツリー ビューの画面行をクリックしてから貼る
- 画面を差し替えるときは **先に旧画面を削除**してから貼ると、同じ画面名で入る
  （残したまま貼ると `ScrHome_1` になる）
- **右クリックメニューの項目位置は画面ごとに変わる。** 一番下の画面には「下へ移動」が無いため
  1 行ぶん上にずれ、同じ座標が「貼り付け」だったり「画面の複製」だったりする。
  座標を覚えず、**メニューを開くたびにラベルを見て押す**
- 画面を全部貼り直すと **`App.StartScreen` が外れる**（Studio のプレビューは
  「選択中の画面」から始まるので気づきにくい）。貼り直したら `StartScreen` を設定し直す
- 貼り付けが失敗すると**画面が消えたまま**になる。エラーダイアログの「表示数を増やす」で
  `PA2108` 等の詳細が読めるので、直してから貼り直す

## AutoLayout の子だけ縦に縮める（`AlignInContainer`）

横方向 AutoLayout の行では、既定（親の `LayoutAlignItems: Stretch`）だと**子が行の高さいっぱいに伸びる**。
`Fill` を持たせたセルは行高さぶんの塗り面になり、隣の列とくっついて 1 枚の帯に見える。

子ごとに上書きするプロパティが **`AlignInContainer`**（実機で採取。データ型: テキスト）。

```
AlignInContainer: =AlignInContainer.Center   # 縦は自前の Height を使い、中央に置かれる
Height:           =26
LayoutMinHeight:  =0                         # 既定 32 が下限として効くので必ず外す
```

**`LayoutMinHeight` の既定 32 を外し忘れると、`Height: =26` にしても 32 で描画される。**

### 列幅は変えずにチップだけ細くする

AutoLayout の主軸（横）は「並び順 × 幅」で決まるので、**セルを細くすると後続の列がまるごと左へずれ、
画面レベルに置いた見出しとの対応が崩れる**。列幅は保ったままチップだけ細くするには、
**前後に空の `ModernText`（スペーサー）を入れて桁を埋める**。

```
列 96px = [スペーサー 20][チップ 56][スペーサー 20]
```

見出しの中心（`X + Width/2`）を列の中心に合わせておくと、チップと見出しが縦に揃う。

> チップを細くすると長い文言が折り返す。このアプリでは「― 設定不可」を
> マトリックスと同じ「―」に統一して幅を詰めた（意味は表の下の注意書きで説明している）。
