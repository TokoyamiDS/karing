"""Sync missing translation keys from en into every other locale.

Why this exists: slang emits a `Translations` interface that every locale class
must implement, and this project keeps strict key parity across all 28 locales.
Adding a key to `en.i18n.json` alone therefore breaks compilation for the other
27. Run this after editing en (and fa, if you have a Persian translation), then
`dart run slang`.

Handles three cases:
  * a whole top-level key missing from a locale -> insert the en block
  * a flat leaf key missing inside a namespace -> insert the en line
  * a top-level scalar key missing             -> insert the en line

Formatting is per-file: locales differ in indentation (en uses 4-space
namespaces, the rest use 2) and line endings, so each insertion is re-indented
and CRLF/LF is preserved.
"""
import glob
import json
import os
import re

I18N = os.path.join("lib", "i18n")
ANCHOR_RE = re.compile(r'^([ \t]*)"NetCheckScreen":\s*\{', re.M)


def load(path):
    with open(path, encoding="utf-8-sig") as f:
        return f.read()


def brace_block(text, start):
    """Given the index of a `"name": {`, return (end_index_of_closing_brace)."""
    j = text.index("{", start)
    depth = 0
    k = j
    while True:
        c = text[k]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    return k


def with_comma(lines):
    """Give the last non-blank line a trailing comma.

    Inserted text is never placed at the very end of the file, so it always
    needs a comma — but the same key may be last in en and therefore lack one.
    """
    out = list(lines)
    for idx in range(len(out) - 1, -1, -1):
        if out[idx].strip():
            s = out[idx].rstrip()
            if s.endswith(","):
                s = s[:-1].rstrip()
            out[idx] = s + ","
            break
    return out


def raw_block(text, name):
    """Raw lines of a top-level `"name": {...},` or scalar, with indent removed."""
    needle = '"%s":' % name
    i = text.index(needle)
    line_start = text.rfind("\n", 0, i) + 1
    indent = text[line_start:i]
    if text[i + len(needle) :].lstrip().startswith("{"):
        end = brace_block(text, i) + 1
    else:
        end = text.index("\n", i)
    end += 1
    lines = text[line_start:end].rstrip("\r\n").split("\n")
    base = len(indent)
    return with_comma([l[base:] if l.strip() else "" for l in lines])


def leaf_line(text, ns, key):
    """Raw (left-trimmed, comma-terminated) line for `"key": ...` in `ns`."""
    i = text.index('"%s":' % ns)
    block = text[i : brace_block(text, i) + 1]
    j = block.index('"%s":' % key)
    line_start = block.rfind("\n", 0, j) + 1
    line_end = block.index("\n", j)
    line = block[line_start:line_end].rstrip()
    if line.endswith(","):
        line = line[:-1].rstrip()
    return line[len(line) - len(line.lstrip()) :] + ","


def main():
    en_raw = load(os.path.join(I18N, "en.i18n.json"))
    en = json.loads(en_raw)
    changed = []

    for path in sorted(glob.glob(os.path.join(I18N, "*.i18n.json"))):
        name = os.path.basename(path)
        text = load(path)
        data = json.loads(text)
        anchor = ANCHOR_RE.search(text)
        if anchor is None:
            print("SKIP (no anchor):", name)
            continue
        indent = anchor.group(1)
        newline = "\r\n" if "\r\n" in text else "\n"
        added = []

        # 1. Whole top-level keys (namespaces and scalars) missing entirely.
        for key in en:
            if key in data:
                continue
            lines = raw_block(en_raw, key)
            body = newline.join((indent + l) if l else "" for l in lines) + newline
            text = text[: anchor.start()] + body + text[anchor.start() :]
            added.append(key)
            data[key] = en[key]
            anchor = ANCHOR_RE.search(text)

        # 2. Flat leaf keys missing inside an existing namespace.
        for ns, en_ns in en.items():
            if not isinstance(en_ns, dict) or ns not in data:
                continue
            if any(isinstance(v, dict) for v in en_ns.values()):
                continue  # nested namespace: only handled wholesale
            missing = [k for k in en_ns if k not in data[ns]]
            if not missing:
                continue
            i = text.index('"%s":' % ns)
            close = brace_block(text, i)
            line_start = text.rfind("\n", 0, close) + 1
            # Match the indentation of an existing key; the closing-brace line
            # is indented less and would produce misaligned output.
            m = re.search(r'\n([ \t]+)"', text[i:close])
            key_indent = m.group(1) if m else indent + "  "
            # The previously-last key may have no comma (it was last), so give
            # it one before appending more keys after it.
            p = line_start - 1
            if p > 0 and text[p - 1] == "\r":
                p -= 1
            while p > 0 and text[p - 1] in " \t":
                p -= 1
            if p > 0 and text[p - 1] not in "{,":
                text = text[:p] + "," + text[p:]
                line_start += 1
            inserted = [key_indent + leaf_line(en_raw, ns, k) for k in missing]
            # These lines go immediately before the closing brace, so the last
            # one must NOT carry a comma.
            last = inserted[-1].rstrip()
            if last.endswith(","):
                last = last[:-1]
            inserted[-1] = last
            body = newline.join(inserted) + newline
            text = text[:line_start] + body + text[line_start:]
            added.append("%s.{ %s }" % (ns, ", ".join(missing)))

        if not added:
            continue
        with open(path, "w", encoding="utf-8-sig", newline="") as f:
            f.write(text)
        changed.append((name, added))

    print("updated %d locales" % len(changed))
    for n, added in changed:
        print("  %-20s %s" % (n, "; ".join(added)))


if __name__ == "__main__":
    main()
