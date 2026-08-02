#!/usr/bin/env python3
"""src/*.pa.yaml の検査。

Power Apps に取り込むまで気づけない壊れ方を、手元で落とすためのもの。

  python3 setup/check-yaml.py

**同じ Properties ブロックに同名のプロパティが 2 つある**と、取り込み時に
`PA1001 ... Duplicate name 'Fill'` で失敗する。厄介なのは:

- `pac canvas pack` は素通しする（パックは成功して、取り込みで初めて落ちる）
- `pac canvas validate` は廃止された
- Python の `yaml.safe_load` も既定では重複を許す（後勝ち）ので気づけない

なので自前で見る。プロパティの値が複数行のクォート形式で書かれていることが
あり（`Fill: '=RGBA(...)\\n\\n  '`）、`Fill: =` だけを探す雑な検査では
見落とすため、キー名だけで突き合わせている。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = sorted((ROOT / "src").glob("*.pa.yaml"))

KEY = re.compile(r"^(\s*)([A-Za-z][A-Za-z0-9_.]*):(?: |$)")
PROPS = re.compile(r"^(\s*)Properties:\s*$")


# コントロールごとの使えるプロパティ。取り込みは通るのに Studio で開くと
# PA2108 Unknown property で落ちるので、手元で気づけるようにしておく。
# 出典: learn.microsoft.com「Text modern control in canvas apps」
_COMMON = {
    "X", "Y", "Width", "Height", "Visible", "DisplayMode",
    # コンテナの子として使うもの
    "AlignInContainer", "FillPortions", "LayoutMinHeight", "LayoutMinWidth",
}
CTRL_PROPS = {
    "ModernText": _COMMON | {
        "Text", "OnSelect", "Wrap", "AutoHeight", "Align", "VerticalAlign",
        "Font", "Size", "Color", "FontWeight", "Italic", "Underline", "Strikethrough",
        "Fill", "BorderColor", "BorderStyle", "BorderThickness",
        "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight",
        "RadiusTopLeft", "RadiusTopRight", "RadiusBottomLeft", "RadiusBottomRight",
    },
    "ModernTextInput": _COMMON | {
        "Default", "Text", "Placeholder", "OnChange", "OnSelect", "Type", "TriggerOutput",
        "MaxLength", "Required", "ValidationState", "Align",
        "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight",
        "Appearance", "BasePaletteColor", "Font", "Size", "Color", "FontWeight",
        "Italic", "Underline", "Strikethrough", "Fill", "BorderColor", "BorderStyle",
        "BorderThickness", "RadiusTopLeft", "RadiusTopRight", "RadiusBottomLeft",
        "RadiusBottomRight", "AccessibleLabel", "ContentLanguage",
    },
}
CTRL_LINE = re.compile(r"^(\s*)- ([A-Za-z0-9_]+):\s*$")
CTRL_DECL = re.compile(r"^\s*Control: ([A-Za-z0-9_]+)@")


def check_props(path):
    """そのコントロールに無いプロパティを (行, 名前, 種類, プロパティ) で返す。"""
    found = []
    name = kind = None
    ind = -1
    for n, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        m = CTRL_LINE.match(line)
        if m:
            name, kind, ind = m.group(2), None, len(m.group(1))
            continue
        d = CTRL_DECL.match(line)
        if d and name:
            kind = d.group(1)
            continue
        if kind not in CTRL_PROPS:
            continue
        k = KEY.match(line)
        if k and len(k.group(1)) == ind + 6 and k.group(2) not in CTRL_PROPS[kind]:
            found.append((n, name, kind, k.group(2)))
    return found


def check(path):
    """同一 Properties ブロック内の重複キーを返す。"""
    found = []
    indent = None
    seen = {}
    for n, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        m = PROPS.match(line)
        if m:
            indent = len(m.group(1)) + 2
            seen = {}
            continue
        if indent is None:
            continue
        k = KEY.match(line)
        if not k:
            continue
        col, name = len(k.group(1)), k.group(2)
        if col != indent:
            # 浅くなったらブロックを抜けた。深いのは値の中なので無視
            if col < indent:
                indent = None
            continue
        if name in seen:
            found.append((n, name, seen[name]))
        seen[name] = n
    return found


def check_parens(path):
    """括弧が釣り合っていない式を (行, プロパティ, ずれ) で返す。

    式の一部を機械的に消したときに閉じ括弧だけ残ると、取り込みは通るのに
    Studio で「予期しない文字があります」になる。
    """
    found = []
    for n, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        m = re.match(r"^\s*([A-Za-z][A-Za-z0-9_]*): =(.*)$", line)
        if not m:
            continue
        depth = 0
        quoted = False
        for ch in m.group(2):
            if ch == '"':
                quoted = not quoted
            elif not quoted:
                depth += (ch == "(") - (ch == ")")
        if depth:
            found.append((n, m.group(1), depth))
    return found


def main():
    if not TARGETS:
        print("src/*.pa.yaml が見つからない", file=sys.stderr)
        return 1
    bad = 0
    for path in TARGETS:
        hits = check(path)
        for n, prop, depth in check_parens(path):
            side = "閉じ括弧が足りない" if depth > 0 else "閉じ括弧が多い"
            print(f"{path.relative_to(ROOT)}:{n}: {prop} の括弧が合わない（{side} {abs(depth)}）")
            bad += 1
        for n, ctrl, kind, prop in check_props(path):
            print(f"{path.relative_to(ROOT)}:{n}: {kind} に '{prop}' は無い（{ctrl}）")
            bad += 1
        rel = path.relative_to(ROOT)
        if hits:
            for n, name, first in hits:
                print(f"{rel}:{n}: 重複したプロパティ '{name}'（最初は {first} 行目）")
            bad += len(hits)
        else:
            print(f"{rel}: OK")
    if bad:
        print(f"\n重複 {bad} 件。取り込み時に PA1001 で失敗する。", file=sys.stderr)
        return 1
    print("\n重複なし")
    return 0


if __name__ == "__main__":
    sys.exit(main())
