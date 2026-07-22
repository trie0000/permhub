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
VerticalAlign: ='TextCanvas.VerticalAlign'.Middle
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

## `ModernText` のスクロールバーと縦位置

高さより内容が高いと**縦スクロールバーが出る**。既定の上下パディング 5px + 5px が効くので、
`Height: =28` / `Size: =15` のような普通のラベルでも出る。画面が細いバーだらけになる。
対策は**上下パディングを 0 にする**こと（`Wrap` は変えない）。

```
PaddingTop: =0
PaddingBottom: =0
```

> **`Wrap: =false` にしてはいけない（重要）。**
> 単一行の折り返しオフにすると、**`VerticalAlign: =Middle` が無効化されてテキストが上詰めになる**。
> ピルやタブの文字が箱の上に寄る。実機で確認済み（`全体`/`個別` ボタンで再現→`Wrap` を戻して中央に復帰）。
> スクロールバーはパディング 0 だけで消えるので、`Wrap` は既定（true）のままにする。
> 逆に言うと、**縦中央にしたいテキストは `Wrap` を false にしない**。

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
