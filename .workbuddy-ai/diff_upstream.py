"""Compare this fork's Dart file set with the public KaringX repo.

Karing's public repo is only a subset of the app source, so this reports what
is missing upstream (i.e. cannot be diffed) as well as what genuinely differs.
"""
import json
import os
import sys
import urllib.request

ROOT = r"D:\Flutter Projects\karing"
API = "https://api.github.com/repos/KaringX/karing/git/trees/main?recursive=1"


def fetch_upstream():
    req = urllib.request.Request(API, headers={"User-Agent": "diff-script"})
    with urllib.request.urlopen(req, timeout=90) as r:
        data = json.load(r)
    return {x["path"] for x in data["tree"] if x["path"].endswith(".dart")}


def local_files():
    out = set()
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "lib")):
        for f in files:
            if f.endswith(".dart"):
                full = os.path.join(dirpath, f)
                out.add(os.path.relpath(full, ROOT).replace(os.sep, "/"))
    return out


def main():
    upstream = fetch_upstream()
    ours = local_files()
    print("dart files — ours: %d, upstream: %d" % (len(ours), len(upstream)))

    only_ours = sorted(ours - upstream)
    only_up = sorted(upstream - ours)
    print("\nnot published upstream (%d) — these CANNOT be diffed:" % len(only_ours))
    for p in only_ours[:14]:
        print("   +", p)
    if len(only_ours) > 14:
        print("   ... and %d more" % (len(only_ours) - 14))

    print("\npresent upstream but absent here (%d):" % len(only_up))
    for p in only_up[:10]:
        print("   -", p)

    shared = sorted(ours & upstream)
    print("\ncomparable files: %d" % len(shared))
    return 0


if __name__ == "__main__":
    sys.exit(main())
