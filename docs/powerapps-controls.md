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

コントロールごとに名前空間が分かれている。**クラシックの `Align.Center` は使えない。**

```
Appearance:    ='ButtonCanvas.Appearance'.Primary
Align:         ='TextCanvas.Align'.Center
VerticalAlign: ='TextCanvas.VerticalAlign'.Middle   ← 構文は通るが描画には効かない（後述）
FontWeight:    ='TextCanvas.FontWeight'.Bold
```

`ModernButton` にも `Color` / `Align` / `FontWeight` / `Fill` / `Icon` / `Layout` がある。

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

## `ModernText` の縦位置とスクロールバー（最重要）

### `VerticalAlign` は効かない（no-op）

`VerticalAlign` はプロパティとして存在し `Middle` を設定してもエラーにならないが、**描画に一切影響しない**。
実機で `Middle` と `Bottom` を隣り合わせで比較したが**同じ位置に描画された**。

**テキストは常に「コンテンツ領域の上端」＝ `PaddingTop` の位置から描画される。**
したがって**縦位置はパディングだけで決まる**。

### 行の高さ（光学行高） = `Size` × 24/13

**`AutoHeight` で測った内容高さ（Size 13 → 18px）を使ってはいけない。**
それで中央寄せすると**約 3px 下がる**。フォントのアセント/ディセントの配分で、
グリフの視覚的な中心が内容ボックスの中心より下にあるため。

見た目を合わせるための「光学行高」は **`Size` × 24/13**。

| Size | 11 | 12 | 13 | 15 | 16 |
|---|---|---|---|---|---|
| 光学行高 | 20 | 22 | 24 | 28 | 30 |

#### 求め方（同じ手順で再校正できる）

**同じ高さの枠を3つ並べ、パディングを変えて1回のプレビューで見比べる。**
1コントロールずつ測ると時間がかかるうえ判断がぶれる。

```
高さ34px の枠3つ → パディング 4 / 6 / 8 を同時に入れる（テキストは同一文字列にする）
  4 = やや上 / 6 = わずかに下 / 8 = 明らかに下  → 最適 5
  → 光学行高 = 34 - 5×2 = 24  → 係数 24/13
```

### 中央寄せの式

```
PaddingTop    = (Height - 行高) / 2      ← これで縦中央になる
PaddingBottom = 0                        ← 0 にしておけばスクロールバーは出ない
```

`PaddingBottom` を 0 にすると内容高さは行高だけになるので、**行高 ≤ Height** である限り
スクロールバーは出ない。逆に既定の 5+5 のままだと `Height: =28` / `Size: =15`（行高 21）で
21 > 28-10 となり**スクロールバーが出る**。

> **誤診の記録（2回やった）。**
> 1回目: 「`Wrap: =false` が `VerticalAlign` を無効化している」→ 誤り。`Wrap` は縦位置に無関係で、
>   `VerticalAlign` は元から効かない。
> 2回目: 行高に `AutoHeight` の実測値 18 を使った → 3px 下がる。正しくは光学行高 24。
>
> どちらも「1コントロールを目測」で判断したのが原因。**同じ高さの枠を並べて相対比較する。**

### 画面サイズを変えてもズレない

パディングは定数だが、**テキスト枠はすべて固定 `Height`・固定 `Size`**（式に依存するものは無い）。
画面サイズで変わるのは `X` と `Width`（`Parent.Width` 基準）だけなので、縦位置は影響を受けない。

```sh
# 「高さが画面サイズに依存するテキスト枠」が無いことの確認（0 件であること）
grep -nE '^\s+Height: =.*Parent\.' src/*.pa.yaml
```

**枠の `Height` か `Size` を変えたら、そのコントロールの `PaddingTop` は計算し直す。**

### 高さの違うコントロールを同じ行に並べるとき

上詰めだった頃は `Y` を揃えれば見た目も揃ったが、**中央寄せにすると `Y + Height/2`（中心）が
揃っていないとズレる**。行見出しなど高さの違うものを横に並べている箇所は中心で合わせ直す。

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

## 貼り付け時の注意

- 数式バー左の**プロパティ名コンボにフォーカスが残っていると `Cmd+V` がそこに入る**。
  ツリー ビューの画面行をクリックしてから貼る
- 画面を差し替えるときは **先に旧画面を削除**してから貼ると、同じ画面名で入る
  （残したまま貼ると `ScrHome_1` になる）
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
