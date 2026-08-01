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


def main():
    if not TARGETS:
        print("src/*.pa.yaml が見つからない", file=sys.stderr)
        return 1
    bad = 0
    for path in TARGETS:
        hits = check(path)
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
