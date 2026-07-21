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
