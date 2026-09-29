#!/usr/bin/env python3
"""Render website/ for a release: bake version, download URL and .dmg SHA-256 into index.html.

  scripts/render-website.py <version> <sha256-of-dmg> <out-dir>

Copies index.html, support.js and images/ into <out-dir> (README.txt and the editor source
"Yeet Website.dc.html" are not published). The download link is /download/<version>/Yeet-<version>.dmg,
served on the VPS by yeet-dl (302 → short-lived presigned URL on B2).

index.html keeps these values in two places — the `data-props` defaults and the `p.x ?? "…"` fallbacks
in the component — so both are rewritten, and the script fails if either is not found.
"""
import html
import json
import re
import shutil
import sys
from pathlib import Path

VERSION_RE = r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?"


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    version, sha256, out = sys.argv[1], sys.argv[2].lower(), Path(sys.argv[3])
    if not re.fullmatch(VERSION_RE, version):
        sys.exit(f"invalid version: {version!r}")
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        sys.exit(f"invalid sha256: {sha256!r}")

    src = Path(__file__).resolve().parent.parent / "website"
    values = {
        "downloadUrl": f"/download/{version}/Yeet-{version}.dmg",
        "version": version,
        "checksum": sha256,
    }

    page = (src / "index.html").read_text(encoding="utf-8")

    # 1. data-props defaults (HTML-escaped JSON inside the attribute)
    m = re.search(r'data-props="([^"]*)"', page)
    if not m:
        sys.exit("data-props not found in index.html")
    props = json.loads(html.unescape(m.group(1)))
    for k, v in values.items():
        if k not in props:
            sys.exit(f"data-props has no {k!r}")
        props[k]["default"] = v
    attr = html.escape(json.dumps(props, ensure_ascii=False, separators=(",", ":")), quote=True)
    page = page[: m.start(1)] + attr + page[m.end(1) :]

    # 2. fallbacks in the component: p.downloadUrl ?? "…"
    for k, v in values.items():
        page, n = re.subn(rf'(p\.{k} \?\? )"[^"]*"', lambda mm: f'{mm.group(1)}{json.dumps(v)}', page)
        if n != 1:
            sys.exit(f"expected exactly one `p.{k} ?? \"…\"` fallback, found {n}")

    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    (out / "index.html").write_text(page, encoding="utf-8")
    shutil.copy2(src / "support.js", out / "support.js")
    shutil.copytree(src / "images", out / "images")
    print(f"rendered {out} — Yeet {version}, {values['downloadUrl']}, sha256 {sha256[:12]}…")


if __name__ == "__main__":
    main()
